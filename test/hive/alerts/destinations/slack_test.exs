defmodule Hive.Alerts.Destinations.SlackTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Alerts.Destinations.Slack, as: SlackDestination
  alias Hive.Alerts.Rule
  alias Hive.Errors.Issue
  alias Hive.Projects.Project
  alias Hive.Slack.Installation

  setup :verify_on_exit!

  defp rule do
    %Rule{
      id: "11111111-1111-1111-1111-111111111111",
      name: "Prod regressions",
      trigger: :regression,
      tier: :incident,
      destination_type: :slack,
      slack_channel_id: "C42",
      slack_mention: :here
    }
  end

  defp issue(overrides \\ %{}) do
    base = %Issue{
      id: "33333333-3333-3333-3333-333333333333",
      title: "boom",
      culprit: "MyApp.blow_up/0",
      level: :error,
      status: :unresolved,
      event_count: 128,
      first_seen: DateTime.add(DateTime.utc_now(), -3600, :second),
      last_seen: DateTime.add(DateTime.utc_now(), -30, :second),
      fingerprint: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
      project: %Project{id: "22222222-2222-2222-2222-222222222222", name: "Widgets"}
    }

    Enum.reduce(overrides, base, fn {k, v}, acc -> Map.put(acc, k, v) end)
  end

  defp connected_installation do
    %Installation{
      id: "44444444-4444-4444-4444-444444444444",
      team_id: "T1",
      team_name: "Test",
      bot_token: "xoxb-test"
    }
  end

  defp find_block(blocks, type, matcher \\ fn _ -> true end) do
    Enum.find(blocks, fn block -> block["type"] == type and matcher.(block) end)
  end

  test "builds a Block Kit payload with header, severity fields, and an open-issue button" do
    parent = self()

    expect(Hive.Slack.API, :post_message, fn _installation, params ->
      send(parent, {:posted, params})
      {:ok, %{"ok" => true}}
    end)

    assert :ok =
             SlackDestination.deliver(
               rule(),
               issue(),
               connected_installation(),
               :regression,
               environment: "production"
             )

    assert_receive {:posted, params}

    blocks = params["blocks"]
    assert is_list(blocks)

    header = find_block(blocks, "header")
    assert header
    assert header["text"]["text"] =~ "Incident"
    assert header["text"]["text"] =~ "Regression"

    mention = find_block(blocks, "section", &(get_in(&1, ["text", "text"]) == "<!here>"))
    assert mention, "expected mention section for :here"

    # Fields section carries level + environment + events + freshness
    fields_section =
      find_block(blocks, "section", fn block ->
        is_list(block["fields"])
      end)

    assert fields_section
    field_text = Enum.map_join(fields_section["fields"], "\n", & &1["text"])
    assert field_text =~ "*Level*"
    assert field_text =~ "error"
    assert field_text =~ "*Environment*"
    assert field_text =~ "production"
    assert field_text =~ "*Events*"
    # `128` events should render as-is (small integer)
    assert field_text =~ "128"
    assert field_text =~ "*Last seen*"
    assert field_text =~ "*First seen*"

    # Actions block with a link back to the issue
    actions = find_block(blocks, "actions")
    assert actions
    button = List.first(actions["elements"])
    assert button["type"] == "button"
    assert String.starts_with?(button["url"], "http")
    assert String.ends_with?(button["url"], "/errors/" <> issue().id)
  end

  test "fallback text carries the severity signals for notifications" do
    expect(Hive.Slack.API, :post_message, fn _installation, params ->
      assert params["text"] =~ "Incident"
      assert params["text"] =~ "Regression"
      assert params["text"] =~ "error"
      assert params["text"] =~ "production"
      assert params["text"] =~ "boom"
      {:ok, %{"ok" => true}}
    end)

    assert :ok =
             SlackDestination.deliver(
               rule(),
               issue(),
               connected_installation(),
               :regression,
               environment: "production"
             )
  end

  test "attention tier uses the ⚠️ marker and no @here" do
    parent = self()

    expect(Hive.Slack.API, :post_message, fn _installation, params ->
      send(parent, {:posted, params})
      {:ok, %{"ok" => true}}
    end)

    attention_rule = %{rule() | tier: :attention, slack_mention: :none}

    assert :ok =
             SlackDestination.deliver(
               attention_rule,
               issue(),
               connected_installation(),
               :new_issue_threshold
             )

    assert_receive {:posted, params}
    header = find_block(params["blocks"], "header")
    assert header["text"]["text"] =~ "Attention"

    refute Enum.any?(params["blocks"], fn b ->
             get_in(b, ["text", "text"]) in ["<!here>", "<!channel>"]
           end)
  end
end

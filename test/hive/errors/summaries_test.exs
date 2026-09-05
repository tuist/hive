defmodule Hive.Errors.SummariesTest do
  use Hive.DataCase, async: true

  alias Hive.Errors.Issue
  alias Hive.Errors.Summaries
  alias Hive.Errors.SummaryRun
  alias Hive.Projects
  alias Hive.Slack.Installation

  @now ~U[2026-09-05 12:01:00Z]
  @config %{enabled: true, schedule: "0 * * * *", slack_channel_id: "C123"}

  test "does nothing when the workflow is disabled" do
    assert {:ok, nil, :disabled} =
             Summaries.run(
               config: %{enabled: false, schedule: "0 * * * *", slack_channel_id: nil}
             )

    refute Repo.exists?(SummaryRun)
  end

  test "generates, validates, posts, and persists one summary for the reporting period" do
    issue = insert_issue!(%{title: "Checkout crashes", level: :fatal, event_count: 42})
    installation = connected_installation!()
    test_pid = self()

    runner = fn input ->
      send(test_pid, {:input, input})

      {:ok,
       %{
         summary: "A fatal checkout error dominates the period.",
         attention: [
           %{issue_id: issue.id, reason: "Fatal severity and 42 captured events."},
           %{issue_id: Ecto.UUID.generate(), reason: "This identifier was not supplied."}
         ]
       }}
    end

    poster = fn ^installation, payload ->
      send(test_pid, {:payload, payload})
      {:ok, %{"ts" => "123.456"}}
    end

    assert {:ok, run, :delivered} =
             Summaries.run(
               config: @config,
               scheduled_for: @now,
               installation: installation,
               runner: runner,
               poster: poster
             )

    assert run.status == :delivered
    assert run.issue_ids == [issue.id]
    assert run.slack_message_ts == "123.456"
    assert run.window_start == ~U[2026-09-04 12:01:00Z]
    assert run.window_end == @now
    assert [%{"issue_id" => issue_id}] = run.attention
    assert issue_id == issue.id

    assert_receive {:input, %{issues: [%{id: issue_id}], omitted_issue_count: 0}}
    assert issue_id == issue.id

    assert_receive {:payload, payload}
    assert payload["channel"] == "C123"
    assert inspect(payload["blocks"]) =~ "Requires special attention"
    assert inspect(payload["blocks"]) =~ "/errors/#{issue.id}"
    refute inspect(payload["blocks"]) =~ "This identifier was not supplied"
  end

  test "retries Slack delivery without invoking the model a second time" do
    issue = insert_issue!(%{})
    installation = connected_installation!()

    assert {:error, :temporary_slack_failure} =
             Summaries.run(
               config: @config,
               scheduled_for: @now,
               installation: installation,
               runner: fn _input ->
                 {:ok,
                  %{
                    summary: "One recent error was captured.",
                    attention: [%{issue_id: issue.id, reason: "It recurred recently."}]
                  }}
               end,
               poster: fn _, _ -> {:error, :temporary_slack_failure} end
             )

    assert %SummaryRun{status: :generated} = Repo.one!(SummaryRun)

    assert {:ok, %SummaryRun{status: :delivered}, :delivered} =
             Summaries.run(
               config: @config,
               scheduled_for: @now,
               installation: installation,
               runner: fn _input -> flunk("the stored model output should be reused") end,
               poster: fn _, _ -> {:ok, %{"ts" => "retry.1"}} end
             )
  end

  test "records an empty period without invoking the model or Slack" do
    assert {:ok, %SummaryRun{status: :empty}, :empty} =
             Summaries.run(
               config: @config,
               scheduled_for: @now,
               runner: fn _input -> flunk("an empty period should not use the model") end,
               poster: fn _, _ -> flunk("an empty period should not post") end
             )
  end

  test "does not repeat a durable provider rejection for unchanged issues" do
    _issue = insert_issue!(%{})

    assert {:error, :llm_credit_limit} =
             Summaries.run(
               config: @config,
               scheduled_for: @now,
               runner: fn _input -> {:error, :llm_credit_limit} end
             )

    assert {:ok, %SummaryRun{status: :failed}, :failed} =
             Summaries.run(
               config: @config,
               scheduled_for: DateTime.add(@now, 60, :second),
               runner: fn _input -> flunk("unchanged rejected input should not be sent again") end
             )

    assert Repo.aggregate(SummaryRun, :count) == 2
  end

  defp insert_issue!(attrs) do
    {:ok, project} = Projects.create_project(%{name: "Storefront", visibility: "private"})

    defaults = %{
      project_id: project.id,
      fingerprint: String.duplicate("a", 64),
      title: "Recent error",
      culprit: "Storefront.checkout/1",
      level: :error,
      status: :unresolved,
      first_seen: ~U[2026-09-05 11:05:00.000000Z],
      last_seen: ~U[2026-09-05 11:55:00.000000Z],
      event_count: 3
    }

    %Issue{}
    |> Issue.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp connected_installation! do
    %Installation{}
    |> Installation.changeset(%{
      team_id: "T123",
      team_name: "Test workspace",
      bot_token: "xoxb-placeholder",
      installed_at: ~U[2026-09-01 00:00:00Z]
    })
    |> Repo.insert!()
  end
end

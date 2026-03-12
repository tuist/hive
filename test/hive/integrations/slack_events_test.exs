defmodule Hive.Integrations.SlackEventsTest do
  use Hive.DataCase, async: false

  alias Hive.Integrations
  alias Hive.Integrations.SlackEvents
  alias Hive.Signals

  defmodule SlackAPIFake do
    def get_user_display_name(_integration, "U123"), do: {:ok, "alice"}
    def get_user_display_name(_integration, "U456"), do: {:ok, "bob"}
    def get_user_display_name(_integration, user_id), do: {:error, {:unknown_user, user_id}}
  end

  setup do
    previous = Application.get_env(:hive, :slack_api)
    Application.put_env(:hive, :slack_api, __MODULE__.SlackAPIFake)
    on_exit(fn -> Application.put_env(:hive, :slack_api, previous) end)

    {:ok, integration} =
      Integrations.create_slack_integration(%{
        name: "Test Slack",
        bot_token: "xoxb-test",
        signing_secret: "secret"
      })

    {:ok, _channel} =
      Integrations.add_slack_channel(integration, %{channel_id: "C123", channel_name: "builds"})

    :ok
  end

  describe "handle_event/1" do
    test "creates a signal with a resolved Slack author" do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "text" => "Build is failing on main",
        "ts" => "1710000000.100000"
      }

      assert {:ok, signal} = SlackEvents.handle_event(payload)
      assert signal.title == "Build is failing on main"
      assert signal.source == "slack"
      assert signal.status == :new
      assert signal.source_author == "alice"
      assert signal.source_channel == "#builds"
      assert signal.source_url == "slack://channel/C123/p1710000000100000"
    end

    test "adds a thread reply to an existing signal with a resolved author" do
      {:ok, signal} =
        Signals.create_signal(%{
          title: "Build is failing on main",
          body: "Started after merging #42",
          source: "slack",
          source_author: "alice",
          source_channel: "#builds",
          source_url: "slack://channel/C123/p1710000000100000"
        })

      payload = %{
        "type" => "message",
        "channel" => "C123",
        "thread_ts" => "1710000000.100000",
        "ts" => "1710000300.200000",
        "user" => "U456",
        "text" => "I can reproduce this locally too"
      }

      assert {:ok, message} = SlackEvents.handle_event(payload)
      assert message.author == "bob"
      assert message.body == "I can reproduce this locally too"
      assert message.source_url == "slack://channel/C123/p1710000300200000"

      fetched_signal = Signals.get_signal(signal.id)
      assert [%{author: "bob"}] = fetched_signal.messages
    end

    test "falls back to the Slack user ID when lookup fails" do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U999",
        "text" => "Unknown author",
        "ts" => "1710000000.100000"
      }

      assert {:ok, signal} = SlackEvents.handle_event(payload)
      assert signal.source_author == "U999"
    end
  end
end

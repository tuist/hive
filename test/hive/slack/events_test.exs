defmodule Hive.Slack.EventsTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Slack
  alias Hive.Slack.Channel
  alias Hive.Slack.Events
  alias Hive.Slack.Installation
  alias Hive.Slack.Message
  alias Hive.Slack.Workers.RespondToConversation
  alias Hive.Slack.Workers.UnfurlLinks

  defp installation! do
    suffix = System.unique_integer([:positive])

    {:ok, installation} =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T#{suffix}",
        team_name: "Workspace #{suffix}",
        bot_token: "xoxb-#{suffix}",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    installation
  end

  defp envelope(event, team_id) do
    %{
      "type" => "event_callback",
      "team_id" => team_id,
      "event" => event
    }
  end

  test "app_mention persists the message and enqueues a thread reply worker" do
    installation = installation!()
    stub(Hive.Agents, :enabled?, fn -> true end)

    event = %{
      "type" => "app_mention",
      "channel" => "C-1",
      "user" => "U-1",
      "ts" => "100.0",
      "text" => "<@U-bot> what's up"
    }

    assert :ok = Events.handle(envelope(event, installation.team_id), installation)
    assert [_message] = Repo.all(Message)
    [%Channel{id: channel_id}] = Repo.all(Channel)

    assert_enqueued(
      worker: RespondToConversation,
      args: %{
        "installation_id" => installation.id,
        "channel_id" => channel_id,
        "thread_ts" => "100.0"
      }
    )
  end

  test "message events persist but do not enqueue a worker" do
    installation = installation!()

    event = %{
      "type" => "message",
      "channel" => "C-1",
      "user" => "U-1",
      "ts" => "200.0",
      "text" => "hello"
    }

    assert :ok = Events.handle(envelope(event, installation.team_id), installation)
    assert [%Message{text: "hello"}] = Repo.all(Message)
    assert all_enqueued() == []
  end

  test "bot messages are skipped" do
    installation = installation!()

    event = %{
      "type" => "message",
      "channel" => "C-1",
      "subtype" => "bot_message",
      "bot_id" => "B-1",
      "ts" => "300.0",
      "text" => "from a bot"
    }

    assert :ok = Events.handle(envelope(event, installation.team_id), installation)
    assert Repo.all(Message) == []
  end

  test "link_shared events enqueue UnfurlLinks with the URLs Slack reports" do
    installation = installation!()

    event = %{
      "type" => "link_shared",
      "channel" => "C-1",
      "message_ts" => "100.0",
      "links" => [
        %{"url" => "https://hive.example.com/specs/1"},
        %{"url" => "https://hive.example.com/meadows/abc"}
      ]
    }

    assert :ok = Events.handle(envelope(event, installation.team_id), installation)

    assert_enqueued(
      worker: UnfurlLinks,
      args: %{
        "installation_id" => installation.id,
        "channel" => "C-1",
        "message_ts" => "100.0",
        "urls" => [
          "https://hive.example.com/specs/1",
          "https://hive.example.com/meadows/abc"
        ]
      }
    )
  end

  test "link_shared events with no links are accepted without enqueuing" do
    installation = installation!()

    event = %{
      "type" => "link_shared",
      "channel" => "C-1",
      "message_ts" => "100.0",
      "links" => []
    }

    assert :ok = Events.handle(envelope(event, installation.team_id), installation)
    assert all_enqueued() == []
  end

  test "unknown event types are accepted without crashing" do
    installation = installation!()

    event = %{"type" => "team_join", "user" => %{"id" => "U-new"}}
    assert :ok = Events.handle(envelope(event, installation.team_id), installation)
  end

  test "app_mention persists the channel + slack user under the installation" do
    installation = installation!()
    stub(Hive.Agents, :enabled?, fn -> false end)

    event = %{
      "type" => "app_mention",
      "channel" => "C-9",
      "user" => "U-9",
      "ts" => "9.0",
      "text" => "hi"
    }

    assert :ok = Events.handle(envelope(event, installation.team_id), installation)

    assert [%Channel{slack_channel_id: "C-9", installation_id: install_id}] =
             Repo.all(Channel)

    assert install_id == installation.id
    assert [%Slack.User{slack_user_id: "U-9"}] = Repo.all(Slack.User)
  end
end

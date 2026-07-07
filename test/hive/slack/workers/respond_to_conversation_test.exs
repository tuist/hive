defmodule Hive.Slack.Workers.RespondToConversationTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Audit.Activity
  alias Hive.Slack
  alias Hive.Slack.API
  alias Hive.Slack.Installation
  alias Hive.Slack.Workers.RespondToConversation

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

  defp channel!(installation, slack_channel_id) do
    {:ok, channel} = Slack.upsert_channel(installation, %{slack_channel_id: slack_channel_id})
    channel
  end

  test "perform/1 posts a reply derived from the thread + agent" do
    installation = installation!()
    channel = channel!(installation, "C-1")

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-agent@example.com",
        provider: "test",
        provider_uid: "slack-agent"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-1", linked_user_id: user.id})

    stub(Hive.Agents, :enabled?, fn -> true end)
    stub(Hive.Agents, :client_opts, fn -> {:ok, [model: "anthropic:test", api_key: "k"]} end)

    installation_id = installation.id

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id}, "C-1", "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-1", "text" => "<@U-bot> hi", "ts" => "1.0"}
         ]
       }}
    end)

    stub(Condukt.Operation, :run, fn _module, :reply_to_thread, args, _opts ->
      assert args["can_create_forage_item"] == true
      {:ok, %{"reply" => "hello!"}}
    end)

    stub(API, :post_message, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-1"
      assert params["thread_ts"] == "1.0"
      assert params["text"] == "hello!"

      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })

    assert %Activity{interface: "worker"} = Repo.get_by!(Activity, action: "slack.replied")
  end

  test "enqueue/4 returns :skipped when agents are disabled" do
    assert :skipped =
             RespondToConversation.enqueue("i", "c", "t", agents_enabled?: fn -> false end)

    assert all_enqueued() == []
  end

  test "perform/1 returns :ok without erroring when the installation is gone" do
    channel_id = Ecto.UUID.generate()

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => Ecto.UUID.generate(),
               "channel_id" => channel_id,
               "thread_ts" => "1.0"
             })
  end
end

defmodule Hive.Slack.Workers.RespondToConversationTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Audit.Activity
  alias Hive.Domains
  alias Hive.Forage.Intake
  alias Hive.GitHub.Issues
  alias Hive.Projects
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

  defp repository! do
    suffix = System.unique_integer([:positive])
    {:ok, project} = Projects.create_project(%{name: "Slack Intake #{suffix}"})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Slack Intake #{suffix}",
        project_id: project.id,
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo#{suffix}"
      })

    github_repository_for_domain!(domain)
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
      assert args["available_github_labels"] == []
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

  test "perform/1 passes configured GitHub labels to the agent" do
    installation = installation!()
    channel = channel!(installation, "C-labels")
    repository = repository!()

    assert {:ok, _settings} =
             Intake.settings()
             |> Intake.update_settings(%{
               "destination" => "github_issue",
               "github_repository_id" => repository.id
             })

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-label-agent@example.com",
        provider: "test",
        provider_uid: "slack-label-agent"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-labels", linked_user_id: user.id})

    expect(Issues, :list_labels, fn %{owner: owner, name: name}, [] ->
      assert owner == repository.owner
      assert name == repository.name

      {:ok,
       [
         %{name: "LiveView", description: "Phoenix LiveView behavior"},
         %{name: "production", description: nil}
       ]}
    end)

    stub(Hive.Agents, :client_opts, fn -> {:ok, [model: "anthropic:test", api_key: "k"]} end)

    installation_id = installation.id

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id}, "C-labels", "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-labels", "text" => "<@U-bot> capture this", "ts" => "1.0"}
         ]
       }}
    end)

    stub(Condukt.Operation, :run, fn _module, :reply_to_thread, args, _opts ->
      assert args["available_github_labels"] == [
               %{"name" => "LiveView", "description" => "Phoenix LiveView behavior"},
               %{"name" => "production"}
             ]

      {:ok, %{"reply" => "captured"}}
    end)

    stub(API, :post_message, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-labels"
      assert params["thread_ts"] == "1.0"
      assert params["text"] == "captured"

      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })
  end

  test "perform/1 posts a setup reply when no model provider is configured" do
    installation = installation!()
    channel = channel!(installation, "C-disabled")
    installation_id = installation.id

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-disabled-agent@example.com",
        provider: "test",
        provider_uid: "slack-disabled-agent"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-1", linked_user_id: user.id})

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id},
                                        "C-disabled",
                                        "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-1", "text" => "<@U-bot> record this", "ts" => "1.0"}
         ]
       }}
    end)

    stub(Hive.Agents, :client_opts, fn -> {:error, :llm_not_configured} end)

    stub(API, :post_message, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-disabled"
      assert params["thread_ts"] == "1.0"
      assert params["text"] =~ "model provider"

      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })
  end

  test "perform/1 posts a fallback reply when the agent submits no result" do
    installation = installation!()
    channel = channel!(installation, "C-no-result")
    installation_id = installation.id

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-no-result-agent@example.com",
        provider: "test",
        provider_uid: "slack-no-result-agent"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-no-result", linked_user_id: user.id})

    stub(Hive.Agents, :client_opts, fn -> {:ok, [model: "anthropic:test", api_key: "k"]} end)

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id},
                                        "C-no-result",
                                        "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-no-result", "text" => "<@U-bot> record this", "ts" => "1.0"}
         ]
       }}
    end)

    stub(Condukt.Operation, :run, fn _module, :reply_to_thread, _args, _opts ->
      {:error, :no_result_submitted}
    end)

    stub(API, :post_message, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-no-result"
      assert params["thread_ts"] == "1.0"
      assert params["text"] =~ "couldn't complete"

      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })
  end

  test "enqueue/4 enqueues even when agents are disabled" do
    assert {:ok, _job} =
             RespondToConversation.enqueue("i", "c", "t", agents_enabled?: fn -> false end)

    assert_enqueued(
      worker: RespondToConversation,
      args: %{
        "installation_id" => "i",
        "channel_id" => "c",
        "thread_ts" => "t"
      }
    )
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

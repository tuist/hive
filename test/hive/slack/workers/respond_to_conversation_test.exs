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
  alias Hive.Agents.Sessions
  alias Hive.Slack.Installation
  alias Hive.Slack.Agents.ConversationAgent
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

  defp stub_agent_stream(reply, assertions \\ fn _prompt -> :ok end) do
    stub(Sessions, :stream, fn ConversationAgent, prompt, opts, consume ->
      assert opts[:load_project_instructions] == false
      assert opts[:max_turns] == 8
      assertions.(prompt)
      consume.([{:text, reply}])
    end)
  end

  defp stub_slack_stream(installation_id, slack_channel_id, thread_ts, reply, stream_ts \\ "2.0") do
    stub(API, :start_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == slack_channel_id
      assert params["thread_ts"] == thread_ts
      assert params["markdown_text"] == reply

      {:ok, %{"ok" => true, "ts" => stream_ts}}
    end)

    stub(API, :stop_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == slack_channel_id
      assert params["ts"] == stream_ts

      {:ok, %{"ok" => true, "ts" => stream_ts}}
    end)
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

    stub_agent_stream("hello!", fn prompt ->
      assert prompt =~ "Can create forage item:\ntrue"
      assert prompt =~ "[triggering mention] 1.0 U-1: <@U-bot> hi"
      refute prompt =~ "Available GitHub labels"
    end)

    stub_slack_stream(installation_id, "C-1", "1.0", "hello!")

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })

    assert %Activity{interface: "worker"} = Repo.get_by!(Activity, action: "slack.replied")
  end

  test "perform/1 keeps streamed text when the agent finishes without a submitted result" do
    installation = installation!()
    channel = channel!(installation, "C-no-result")
    reply = "The reply was already streamed."

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-no-result@example.com",
        provider: "test",
        provider_uid: "slack-no-result"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-no-result", linked_user_id: user.id})

    installation_id = installation.id

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id},
                                        "C-no-result",
                                        "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-no-result", "text" => "<@U-bot> try again", "ts" => "1.0"}
         ]
       }}
    end)

    stub(Sessions, :stream, fn ConversationAgent, _prompt, _opts, consume ->
      consume.([{:text, reply}, {:error, :no_result_submitted}])
    end)

    stub(API, :start_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-no-result"
      assert params["thread_ts"] == "1.0"
      assert params["markdown_text"] == reply

      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    stub(API, :stop_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-no-result"
      assert params["ts"] == "2.0"

      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    reject(&API.post_message/2)

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })

    assert %Activity{interface: "worker"} = Repo.get_by!(Activity, action: "slack.replied")
  end

  test "perform/1 leaves configured GitHub labels out until the agent asks for them" do
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

    reject(&Issues.list_labels/2)

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

    stub_agent_stream("captured", fn prompt ->
      assert prompt =~ "[triggering mention] 1.0 U-labels: <@U-bot> capture this"
      refute prompt =~ "Phoenix LiveView behavior"
      refute prompt =~ "Available GitHub labels"
    end)

    stub_slack_stream(installation_id, "C-labels", "1.0", "captured")

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })
  end

  test "perform/1 uses the triggering mention instead of the latest thread message" do
    installation = installation!()
    channel = channel!(installation, "C-retry")

    {:ok, requester} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-retry-requester@example.com",
        provider: "test",
        provider_uid: "slack-retry-requester"
      })

    {:ok, other_user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-retry-other@example.com",
        provider: "test",
        provider_uid: "slack-retry-other"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{
        slack_user_id: "U-requester",
        linked_user_id: requester.id
      })

    {:ok, _other_slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-other", linked_user_id: other_user.id})

    installation_id = installation.id

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id}, "C-retry", "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{
             "user" => "U-requester",
             "text" => "<@U-bot> record the LiveView websocket issue",
             "ts" => "1.0"
           },
           %{"user" => "U-other", "text" => ":ignored", "ts" => "2.0"},
           %{"user" => "U-requester", "text" => "Working on the fix", "ts" => "3.0"},
           %{"user" => "U-requester", "text" => "<@U-bot> can you try again?", "ts" => "4.0"},
           %{"user" => "U-other", "text" => "later unrelated message", "ts" => "5.0"}
         ]
       }}
    end)

    stub_agent_stream("retrying", fn prompt ->
      assert prompt =~ "[triggering mention] 4.0 U-requester: <@U-bot> can you try again?"
      assert prompt =~ "Can create forage item:\ntrue"
      assert prompt =~ "later unrelated message"
      assert length(:binary.matches(prompt, "<@U-bot> can you try again?")) == 1
    end)

    stub_slack_stream(installation_id, "C-retry", "1.0", "retrying", "6.0")

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0",
               "message_ts" => "4.0"
             })
  end

  test "perform/1 bounds long threads while retaining the root, mention, and recent context" do
    installation = installation!()
    channel = channel!(installation, "C-long-thread")
    installation_id = installation.id

    messages =
      Enum.map(1..12, fn index ->
        prefix =
          case index do
            1 -> "root-context "
            2 -> "<@U-bot> summarize the decision "
            12 -> "latest-context "
            _index -> "middle-#{index} "
          end

        %{
          "user" => "U#{index}",
          "text" => prefix <> String.duplicate("x", 8_000),
          "ts" => "#{index}.0"
        }
      end)

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id},
                                        "C-long-thread",
                                        "1.0" ->
      {:ok, %{"ok" => true, "messages" => messages}}
    end)

    stub_agent_stream("bounded", fn prompt ->
      assert prompt =~ "root-context"
      assert prompt =~ "[triggering mention] 2.0 U2: <@U-bot> summarize the decision"
      assert prompt =~ "latest-context"

      assert prompt =~
               "Earlier messages omitted because the thread exceeded the context budget:\n7"

      assert String.length(prompt) < 57_000
    end)

    stub_slack_stream(installation_id, "C-long-thread", "1.0", "bounded", "13.0")

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0",
               "message_ts" => "2.0"
             })
  end

  test "perform/1 falls back to the locally stored mention when Slack thread history fails" do
    installation = installation!()
    channel = channel!(installation, "C-local")

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-local-agent@example.com",
        provider: "test",
        provider_uid: "slack-local-agent"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-local", linked_user_id: user.id})

    {:ok, _message} =
      Slack.insert_message(installation, channel, %{
        slack_user_id: "U-local",
        slack_ts: "2.0",
        thread_ts: "1.0",
        text: "<@U-bot> record this from the event payload",
        raw_payload: %{}
      })

    installation_id = installation.id

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id}, "C-local", "1.0" ->
      {:error, {:slack_api_error, "missing_scope"}}
    end)

    stub_agent_stream("handled locally", fn prompt ->
      assert prompt =~
               "[triggering mention] 2.0 U-local: <@U-bot> record this from the event payload"

      assert prompt =~ "Can create forage item:\ntrue"
    end)

    stub_slack_stream(installation_id, "C-local", "1.0", "handled locally", "3.0")

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0",
               "message_ts" => "2.0"
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

    stub(Sessions, :stream, fn ConversationAgent, _prompt, _opts, _consume ->
      {:error, :llm_not_configured}
    end)

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

    stub(Sessions, :stream, fn ConversationAgent, _prompt, _opts, consume ->
      consume.([])
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

  test "perform/1 posts a fallback reply when the agent run fails" do
    installation = installation!()
    channel = channel!(installation, "C-agent-error")
    installation_id = installation.id

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-agent-error@example.com",
        provider: "test",
        provider_uid: "slack-agent-error"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-agent-error", linked_user_id: user.id})

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id},
                                        "C-agent-error",
                                        "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-agent-error", "text" => "<@U-bot> record this", "ts" => "1.0"}
         ]
       }}
    end)

    stub(Sessions, :stream, fn ConversationAgent, _prompt, _opts, consume ->
      consume.([{:error, :provider_failed}])
    end)

    stub(API, :post_message, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-agent-error"
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

  test "perform/1 appends later text chunks to the Slack stream" do
    installation = installation!()
    channel = channel!(installation, "C-stream")
    installation_id = installation.id
    first_chunk = String.duplicate("a", 80)
    second_chunk = " " <> String.duplicate("b", 80)

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-stream-agent@example.com",
        provider: "test",
        provider_uid: "slack-stream-agent"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-stream", linked_user_id: user.id})

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id}, "C-stream", "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-stream", "text" => "<@U-bot> stream this", "ts" => "1.0"}
         ]
       }}
    end)

    stub(Sessions, :stream, fn ConversationAgent, _prompt, _opts, consume ->
      consume.([{:text, first_chunk}, {:text, second_chunk}])
    end)

    stub(API, :start_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-stream"
      assert params["thread_ts"] == "1.0"
      assert params["markdown_text"] == first_chunk

      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    stub(API, :append_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-stream"
      assert params["ts"] == "2.0"
      assert params["markdown_text"] == second_chunk

      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    stub(API, :stop_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-stream"
      assert params["ts"] == "2.0"

      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })
  end

  test "perform/1 falls back to message updates when Slack stream start fails" do
    installation = installation!()
    channel = channel!(installation, "C-update")
    installation_id = installation.id

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-update-agent@example.com",
        provider: "test",
        provider_uid: "slack-update-agent"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-update", linked_user_id: user.id})

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id}, "C-update", "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-update", "text" => "<@U-bot> stream this", "ts" => "1.0"}
         ]
       }}
    end)

    stub_agent_stream("fallback text")

    stub(API, :start_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-update"
      assert params["thread_ts"] == "1.0"
      assert params["markdown_text"] == "fallback text"

      {:error, {:slack_api_error, "method_not_supported"}}
    end)

    stub(API, :post_message, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-update"
      assert params["thread_ts"] == "1.0"
      assert params["text"] == "fallback text"

      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })
  end

  test "perform/1 confirms and records a reply when the agent only runs a tool" do
    installation = installation!()
    channel = channel!(installation, "C-tool-only")
    installation_id = installation.id

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-tool-only@example.com",
        provider: "test",
        provider_uid: "slack-tool-only"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-tool-only", linked_user_id: user.id})

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id},
                                        "C-tool-only",
                                        "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-tool-only", "text" => "<@U-bot> record this", "ts" => "1.0"}
         ]
       }}
    end)

    stub(Sessions, :stream, fn ConversationAgent, _prompt, _opts, consume ->
      consume.([
        {:tool_call, "create_forage_item", "call-1", %{}},
        {:tool_result, "call-1", {:ok, %{}}}
      ])
    end)

    stub(API, :post_message, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-tool-only"
      assert params["thread_ts"] == "1.0"
      assert params["text"] == "Done."

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

  test "perform/1 finalizes the streamed message in place when the agent errors mid-stream" do
    installation = installation!()
    channel = channel!(installation, "C-stream-error")
    installation_id = installation.id
    first_chunk = String.duplicate("a", 80)

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-stream-error@example.com",
        provider: "test",
        provider_uid: "slack-stream-error"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-stream-error", linked_user_id: user.id})

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id},
                                        "C-stream-error",
                                        "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-stream-error", "text" => "<@U-bot> stream this", "ts" => "1.0"}
         ]
       }}
    end)

    stub(Sessions, :stream, fn ConversationAgent, _prompt, _opts, consume ->
      consume.([{:text, first_chunk}, {:error, :provider_failed}])
    end)

    stub(API, :start_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["markdown_text"] == first_chunk
      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    test_pid = self()

    stub(API, :append_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["ts"] == "2.0"
      send(test_pid, {:append, params["markdown_text"]})
      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    stub(API, :stop_stream, fn %Installation{id: ^installation_id}, params ->
      assert params["ts"] == "2.0"
      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    # The partial stream is finalized in place; no separate failure message.
    reject(&API.post_message/2)

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })

    assert_received {:append, note}
    assert note =~ "couldn't finish"
    refute Repo.get_by(Activity, action: "slack.replied")
  end

  test "perform/1 overwrites the fallback message when the agent errors after the stream fallback" do
    installation = installation!()
    channel = channel!(installation, "C-update-error")
    installation_id = installation.id
    first_chunk = String.duplicate("a", 80)

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-update-error@example.com",
        provider: "test",
        provider_uid: "slack-update-error"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-update-error", linked_user_id: user.id})

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id},
                                        "C-update-error",
                                        "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-update-error", "text" => "<@U-bot> stream this", "ts" => "1.0"}
         ]
       }}
    end)

    stub(Sessions, :stream, fn ConversationAgent, _prompt, _opts, consume ->
      consume.([{:text, first_chunk}, {:error, :provider_failed}])
    end)

    stub(API, :start_stream, fn %Installation{id: ^installation_id}, _params ->
      {:error, {:slack_api_error, "method_not_supported"}}
    end)

    stub(API, :post_message, fn %Installation{id: ^installation_id}, params ->
      assert params["text"] == first_chunk
      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    test_pid = self()

    stub(API, :update_message, fn %Installation{id: ^installation_id}, params ->
      assert params["ts"] == "2.0"
      send(test_pid, {:update, params["text"]})
      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    assert :ok =
             perform_job(RespondToConversation, %{
               "installation_id" => installation.id,
               "channel_id" => channel.id,
               "thread_ts" => "1.0"
             })

    assert_received {:update, text}
    assert text =~ "couldn't finish"
    refute Repo.get_by(Activity, action: "slack.replied")
  end

  test "perform/1 retries the stream stop and still succeeds when the first stop fails" do
    installation = installation!()
    channel = channel!(installation, "C-stop-retry")
    installation_id = installation.id

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "slack-stop-retry@example.com",
        provider: "test",
        provider_uid: "slack-stop-retry"
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{slack_user_id: "U-stop-retry", linked_user_id: user.id})

    stub(API, :list_thread_messages, fn %Installation{id: ^installation_id},
                                        "C-stop-retry",
                                        "1.0" ->
      {:ok,
       %{
         "ok" => true,
         "messages" => [
           %{"user" => "U-stop-retry", "text" => "<@U-bot> hi", "ts" => "1.0"}
         ]
       }}
    end)

    stub_agent_stream("hello!")

    stub(API, :start_stream, fn %Installation{id: ^installation_id}, _params ->
      {:ok, %{"ok" => true, "ts" => "2.0"}}
    end)

    API
    |> expect(:stop_stream, fn %Installation{id: ^installation_id}, _params ->
      {:error, {:slack_api_error, "ratelimited"}}
    end)
    |> expect(:stop_stream, fn %Installation{id: ^installation_id}, _params ->
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

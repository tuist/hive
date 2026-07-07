defmodule Hive.Slack.Workers.RespondToConversation do
  @moduledoc """
  Replies in a Slack thread where Hive's bot was @-mentioned. Fetches
  the thread, runs `Hive.Slack.Agents.ConversationAgent` through
  `Hive.Agents.Sessions`, posts the reply via `Hive.Slack.API`.

  Stays dormant when no LLM is configured or the installation has been
  disconnected, returning `:skipped` so the job doesn't retry forever.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: 300, states: :incomplete]

  require Logger

  alias Hive.Agents.Sessions
  alias Hive.Audit
  alias Hive.Forage.Intake
  alias Hive.Slack
  alias Hive.Slack.Agents.ConversationAgent
  alias Hive.Slack.API
  alias Hive.Slack.Installation

  def enqueue(installation_id, channel_id, thread_ts, opts \\ [])
      when is_binary(installation_id) and is_binary(channel_id) and is_binary(thread_ts) do
    agents_enabled? = Keyword.get(opts, :agents_enabled?, &Hive.Agents.enabled?/0)

    if agents_enabled?.() do
      %{
        "installation_id" => installation_id,
        "channel_id" => channel_id,
        "thread_ts" => thread_ts
      }
      |> new()
      |> Oban.insert()
    else
      :skipped
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "installation_id" => installation_id,
          "channel_id" => channel_id,
          "thread_ts" => thread_ts
        }
      }) do
    with %{} = installation <- Slack.get_installation(installation_id),
         true <- Installation.connected?(installation) || {:skipped, :disconnected},
         {:ok, %{"messages" => thread_messages}} <-
           API.list_thread_messages(installation, slack_channel_id_for(channel_id), thread_ts),
         %{mention_text: mention_text, thread: thread} <- summarize_thread(thread_messages),
         requester_user = resolve_requester_user(installation, thread),
         {:ok, %{"reply" => reply}} <-
           run_conversation_agent(
             %{
               "mention_text" => mention_text,
               "thread" => thread,
               "can_create_forage_item" => not is_nil(requester_user)
             },
             requester_user
           ),
         {:ok, _} <-
           API.post_message(installation, %{
             "channel" => slack_channel_id_for(channel_id),
             "thread_ts" => thread_ts,
             "text" => reply
           }) do
      Audit.record("slack.replied", %{
        actor: Audit.agent_actor("slack.conversation"),
        interface: "worker",
        target_type: "slack_installation",
        target_id: installation.id,
        target_label: installation.team_name || installation.team_id,
        metadata: %{
          channel_id: channel_id,
          thread_ts: thread_ts
        }
      })

      :ok
    else
      nil ->
        Logger.info(
          "[Slack.RespondToConversation] installation #{installation_id} no longer exists"
        )

        :ok

      {:skipped, _} ->
        :ok

      {:error, :llm_not_configured} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp slack_channel_id_for(channel_id) do
    case Hive.Repo.get(Hive.Slack.Channel, channel_id) do
      nil -> raise "slack channel #{channel_id} not found"
      channel -> channel.slack_channel_id
    end
  end

  defp summarize_thread([]), do: %{mention_text: "", thread: []}

  defp summarize_thread(messages) do
    thread =
      Enum.map(messages, fn message ->
        %{
          "user" => message["user"] || message["bot_id"] || "",
          "text" => message["text"] || "",
          "ts" => message["ts"] || ""
        }
      end)

    mention_text =
      messages
      |> List.last()
      |> Map.get("text", "")

    %{mention_text: mention_text, thread: thread}
  end

  defp resolve_requester_user(installation, thread) do
    thread
    |> List.last()
    |> case do
      %{"user" => slack_user_id} when is_binary(slack_user_id) and slack_user_id != "" ->
        case Slack.resolve_hive_user(installation, slack_user_id) do
          {:ok, user} -> user
          {:error, _reason} -> nil
        end

      _message ->
        nil
    end
  end

  defp run_conversation_agent(input, nil) do
    Sessions.run_operation(ConversationAgent, :reply_to_thread, input)
  end

  defp run_conversation_agent(input, requester_user) do
    Intake.with_requester(requester_user, fn ->
      Sessions.run_operation(ConversationAgent, :reply_to_thread, input)
    end)
  end
end

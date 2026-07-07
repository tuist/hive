defmodule Hive.Slack.Workers.RespondToConversation do
  @moduledoc """
  Replies in a Slack thread where Hive's bot was @-mentioned. Fetches
  the thread, runs `Hive.Slack.Agents.ConversationAgent` through
  `Hive.Agents.Sessions`, posts the reply via `Hive.Slack.API`.

  Posts a short setup note when no model provider is configured. Stays
  dormant when the installation has been disconnected, returning
  `:skipped` so the job doesn't retry forever.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: 300, states: :incomplete]

  require Logger

  alias Hive.Agents.Sessions
  alias Hive.Audit
  alias Hive.Auth
  alias Hive.Forage.Intake
  alias Hive.Repo
  alias Hive.Slack
  alias Hive.Slack.Agents.ConversationAgent
  alias Hive.Slack.API
  alias Hive.Slack.Message
  alias Hive.Slack.Installation

  import Ecto.Query

  def enqueue(installation_id, channel_id, thread_ts, opts \\ [])
      when is_binary(installation_id) and is_binary(channel_id) and is_binary(thread_ts) do
    %{
      "installation_id" => installation_id,
      "channel_id" => channel_id,
      "thread_ts" => thread_ts
    }
    |> maybe_put_arg("message_ts", Keyword.get(opts, :message_ts))
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "installation_id" => installation_id,
            "channel_id" => channel_id,
            "thread_ts" => thread_ts
          } = args
      }) do
    with %{} = installation <- Slack.get_installation(installation_id),
         true <- Installation.connected?(installation) || {:skipped, :disconnected} do
      respond_to_thread(
        installation,
        channel_id,
        thread_ts,
        Map.get(args, "message_ts") || thread_ts
      )
    else
      nil ->
        Logger.info(
          "[Slack.RespondToConversation] installation #{installation_id} no longer exists"
        )

        :ok

      {:skipped, _} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp respond_to_thread(installation, channel_id, thread_ts, message_ts) do
    slack_channel_id = slack_channel_id_for(channel_id)
    local_messages = local_thread_messages(channel_id, thread_ts, message_ts)

    with {:ok, thread_messages} <-
           thread_messages(installation, slack_channel_id, thread_ts, local_messages),
         %{mention_text: mention_text, mention_user: mention_user, thread: thread} <-
           summarize_thread(thread_messages, message_ts),
         requester_user = resolve_requester_user(installation, mention_user),
         {:ok, %{"reply" => reply}} <-
           run_conversation_agent(
             %{
               "mention_text" => mention_text,
               "thread" => thread,
               "can_create_forage_item" => not is_nil(requester_user),
               "available_github_labels" => available_github_labels(requester_user)
             },
             requester_user
           ),
         {:ok, _} <-
           API.post_message(installation, %{
             "channel" => slack_channel_id,
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
      {:error, :llm_not_configured} ->
        post_model_provider_required_message(installation, slack_channel_id, thread_ts)

      {:error, reason} when reason in [:no_result_submitted] ->
        post_agent_response_failed_message(installation, slack_channel_id, thread_ts, reason)

      {:error, {:invalid_output, _reason} = reason} ->
        post_agent_response_failed_message(installation, slack_channel_id, thread_ts, reason)

      {:error, reason} ->
        post_agent_response_failed_message(installation, slack_channel_id, thread_ts, reason)
    end
  end

  defp slack_channel_id_for(channel_id) do
    case Hive.Repo.get(Hive.Slack.Channel, channel_id) do
      nil -> raise "slack channel #{channel_id} not found"
      channel -> channel.slack_channel_id
    end
  end

  defp thread_messages(installation, slack_channel_id, thread_ts, local_messages) do
    case API.list_thread_messages(installation, slack_channel_id, thread_ts) do
      {:ok, %{"messages" => remote_messages}} when is_list(remote_messages) ->
        {:ok, merge_thread_messages(remote_messages, local_messages)}

      {:ok, body} when local_messages != [] ->
        Logger.warning(
          "[Slack.RespondToConversation] Slack thread response did not include messages, using local messages: #{inspect(body)}"
        )

        {:ok, local_messages}

      {:ok, body} ->
        {:error, {:slack_thread_unexpected, body}}

      {:error, reason} when local_messages != [] ->
        Logger.warning(
          "[Slack.RespondToConversation] Could not fetch Slack thread, using local messages: #{inspect(reason)}"
        )

        {:ok, local_messages}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp merge_thread_messages(remote_messages, local_messages) do
    (Enum.map(remote_messages, &message_context/1) ++ local_messages)
    |> Enum.uniq_by(& &1["ts"])
    |> Enum.sort_by(&slack_ts_sort_key(&1["ts"]))
  end

  defp local_thread_messages(channel_id, thread_ts, message_ts) do
    Message
    |> where([message], message.channel_id == ^channel_id)
    |> where(
      [message],
      message.slack_ts == ^thread_ts or message.thread_ts == ^thread_ts or
        message.slack_ts == ^message_ts
    )
    |> Repo.all()
    |> Enum.map(&message_context/1)
    |> Enum.sort_by(&slack_ts_sort_key(&1["ts"]))
  end

  defp summarize_thread([], _message_ts), do: %{mention_text: "", mention_user: nil, thread: []}

  defp summarize_thread(messages, message_ts) do
    mention_message =
      Enum.find(messages, &(&1["ts"] == message_ts)) || List.last(messages) || %{}

    %{
      mention_text: Map.get(mention_message, "text", ""),
      mention_user: Map.get(mention_message, "user"),
      thread: messages
    }
  end

  defp message_context(%Message{} = message) do
    %{
      "user" => message.slack_user_id || "",
      "text" => message.text || "",
      "ts" => message.slack_ts || ""
    }
  end

  defp message_context(message) when is_map(message) do
    %{
      "user" => message["user"] || message["bot_id"] || "",
      "text" => message["text"] || "",
      "ts" => message["ts"] || ""
    }
  end

  defp slack_ts_sort_key(slack_ts) when is_binary(slack_ts) do
    case String.split(slack_ts, ".", parts: 2) do
      [seconds, fraction] -> {parse_integer(seconds), String.pad_trailing(fraction, 9, "0")}
      [seconds] -> {parse_integer(seconds), ""}
    end
  end

  defp slack_ts_sort_key(_slack_ts), do: {0, ""}

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> 0
    end
  end

  defp resolve_requester_user(installation, slack_user_id)
       when is_binary(slack_user_id) and slack_user_id != "" do
    case Slack.resolve_hive_user(installation, slack_user_id) do
      {:ok, user} -> user
      {:error, _reason} -> nil
    end
  end

  defp resolve_requester_user(_installation, _slack_user_id), do: nil

  defp available_github_labels(nil), do: []

  defp available_github_labels(requester_user) do
    if Auth.member?(requester_user) do
      fetch_available_github_labels()
    else
      []
    end
  end

  defp fetch_available_github_labels do
    case Intake.available_github_labels() do
      {:ok, labels} ->
        labels
        |> Enum.map(&github_label_context/1)
        |> Enum.take(100)

      {:error, reason} ->
        Logger.info("[Slack.RespondToConversation] GitHub labels unavailable: #{inspect(reason)}")
        []
    end
  end

  defp github_label_context(%{name: name} = label) do
    %{"name" => name}
    |> maybe_put("description", Map.get(label, :description))
  end

  defp maybe_put(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_arg(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put_arg(map, key, value), do: Map.put(map, key, value)

  defp run_conversation_agent(input, nil) do
    Sessions.run_operation(ConversationAgent, :reply_to_thread, input)
  end

  defp run_conversation_agent(input, requester_user) do
    Intake.with_requester(requester_user, fn ->
      Sessions.run_operation(ConversationAgent, :reply_to_thread, input)
    end)
  end

  defp post_model_provider_required_message(installation, slack_channel_id, thread_ts) do
    API.post_message(installation, %{
      "channel" => slack_channel_id,
      "thread_ts" => thread_ts,
      "text" =>
        "Hive's assistant is not connected to a model provider yet, so I can't process Slack mentions. An instance admin can configure one in Ops -> Inference."
    })
    |> case do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp post_agent_response_failed_message(installation, slack_channel_id, thread_ts, reason) do
    Logger.warning(
      "[Slack.RespondToConversation] Agent did not return a Slack reply: #{inspect(reason)}"
    )

    API.post_message(installation, %{
      "channel" => slack_channel_id,
      "thread_ts" => thread_ts,
      "text" =>
        "I couldn't complete that request because the assistant did not produce a reply. Please try again with a bit more detail."
    })
    |> case do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule Hive.Slack.Workers.RespondToConversation do
  @moduledoc """
  Replies in a Slack thread where Hive's bot was @-mentioned. Fetches
  the thread, runs `Hive.Slack.Agents.ConversationAgent` through
  `Hive.Agents.Sessions`, and streams the reply via `Hive.Slack.API`.

  Posts a short setup note when no model provider is configured. Stays
  dormant when the installation has been disconnected, returning
  `:skipped` so the job doesn't retry forever.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: 300, states: :incomplete]

  require Logger

  @update_interval_ms 900
  @min_update_chars 80
  @max_thread_chars 48_000
  @max_message_chars 8_000

  @no_reply_message "I couldn't complete that request because the assistant did not produce a reply. Please try again with a bit more detail."
  @interrupted_message "I couldn't finish that reply. Please try again."
  @interrupted_stream_note "\n\n_" <> @interrupted_message <> "_"
  @tool_only_ack "Done."

  alias Hive.Agents.Sessions
  alias Hive.Audit
  alias Hive.Forage.Intake
  alias Hive.Repo
  alias Hive.Slack
  alias Hive.Slack.Agents.ConversationAgent
  alias Hive.Slack.API
  alias Hive.Slack.FlightCommands
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
         %{
           mention_user: mention_user,
           thread: thread,
           omitted_thread_messages: omitted_thread_messages
         } <-
           summarize_thread(thread_messages, message_ts),
         requester_user = resolve_requester_user(installation, mention_user),
         input = %{
           "thread" => thread,
           "omitted_thread_messages" => omitted_thread_messages,
           "can_create_forage_item" => not is_nil(requester_user)
         },
         {:ok, _reply} <-
           handle_request(
             input,
             requester_user,
             installation,
             slack_channel_id,
             thread_ts
           ) do
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

      {:error, {:notified, _reason}} ->
        :ok

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

  defp summarize_thread([], _message_ts) do
    %{mention_user: nil, thread: [], omitted_thread_messages: 0}
  end

  defp summarize_thread(messages, message_ts) do
    {thread, omitted_thread_messages} = compact_thread(messages, message_ts)

    triggering_message =
      Enum.find(thread, &(&1["ts"] == message_ts)) || List.last(thread) || %{}

    thread =
      Enum.map(thread, fn message ->
        Map.put(message, "triggering_mention", message["ts"] == triggering_message["ts"])
      end)

    %{
      mention_user: Map.get(triggering_message, "user"),
      thread: thread,
      omitted_thread_messages: omitted_thread_messages
    }
  end

  defp compact_thread(messages, message_ts) do
    messages = Enum.map(messages, &truncate_message_context/1)
    root = List.first(messages)
    mention = Enum.find(messages, &(&1["ts"] == message_ts))

    protected =
      [root, mention]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1["ts"])

    protected_timestamps = MapSet.new(protected, & &1["ts"])
    remaining_chars = max(@max_thread_chars - thread_size(protected), 0)

    {recent, _remaining_chars} =
      messages
      |> Enum.reject(&MapSet.member?(protected_timestamps, &1["ts"]))
      |> Enum.reverse()
      |> Enum.reduce({[], remaining_chars}, fn message, {selected, available} ->
        size = thread_size([message])

        if size <= available do
          {[message | selected], available - size}
        else
          {selected, available}
        end
      end)

    selected =
      (protected ++ recent)
      |> Enum.uniq_by(& &1["ts"])
      |> Enum.sort_by(&slack_ts_sort_key(&1["ts"]))

    {selected, length(messages) - length(selected)}
  end

  defp truncate_message_context(message) do
    Map.update(message, "text", "", &String.slice(&1, 0, @max_message_chars))
  end

  defp thread_size(messages) do
    Enum.reduce(messages, 0, fn message, total ->
      urls_size = Enum.reduce(message["urls"] || [], 0, &(String.length(&1) + &2))

      total + String.length(message["user"] || "") + String.length(message["text"] || "") +
        urls_size + 32
    end)
  end

  defp message_context(%Message{} = message) do
    %{
      "user" => message.slack_user_id || "",
      "text" => message.text || "",
      "ts" => message.slack_ts || "",
      "urls" => evidence_urls(message.raw_payload || %{})
    }
  end

  defp message_context(message) when is_map(message) do
    %{
      "user" => message["user"] || message["bot_id"] || "",
      "text" => message["text"] || "",
      "ts" => message["ts"] || "",
      "urls" => evidence_urls(message)
    }
  end

  defp evidence_urls(payload) do
    payload
    |> collect_strings()
    |> Enum.flat_map(&Regex.scan(~r{https?://[^\s<>"|\\]+}, &1))
    |> Enum.map(&hd/1)
    |> Enum.map(&Regex.replace(~r/[.,)\]]+\z/, &1, ""))
    |> Enum.uniq()
    |> Enum.take(20)
  end

  defp collect_strings(value) when is_binary(value), do: [value]
  defp collect_strings(value) when is_list(value), do: Enum.flat_map(value, &collect_strings/1)

  defp collect_strings(value) when is_map(value),
    do: value |> Map.values() |> Enum.flat_map(&collect_strings/1)

  defp collect_strings(_value), do: []

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

  defp maybe_put_arg(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put_arg(map, key, value), do: Map.put(map, key, value)

  defp handle_request(input, requester_user, installation, slack_channel_id, thread_ts) do
    case FlightCommands.handle(
           input["thread"],
           requester_user,
           installation,
           slack_channel_id,
           thread_ts
         ) do
      :not_a_command ->
        run_conversation_agent(
          input,
          requester_user,
          installation,
          slack_channel_id,
          thread_ts
        )

      {:handled, flight} ->
        {:ok, flight || :handled}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_conversation_agent(input, nil, installation, slack_channel_id, thread_ts) do
    stream_conversation_agent(input, installation, slack_channel_id, thread_ts)
  end

  defp run_conversation_agent(input, requester_user, installation, slack_channel_id, thread_ts) do
    Intake.with_requester(requester_user, fn ->
      stream_conversation_agent(input, installation, slack_channel_id, thread_ts)
    end)
  end

  defp stream_conversation_agent(input, installation, slack_channel_id, thread_ts) do
    prompt = ConversationAgent.build_prompt(input)

    Sessions.stream(
      ConversationAgent,
      prompt,
      [load_project_instructions: false, max_turns: 8],
      fn events ->
        events
        |> Enum.reduce_while(initial_stream_state(), fn event, state ->
          handle_stream_event(event, state, installation, slack_channel_id, thread_ts)
        end)
        |> finalize_stream_result(installation, slack_channel_id, thread_ts)
      end
    )
  end

  defp handle_stream_event({:text, chunk}, state, installation, slack_channel_id, thread_ts)
       when is_binary(chunk) do
    state = %{state | text: state.text <> chunk}

    if should_update?(state) do
      state = flush_response(state, installation, slack_channel_id, thread_ts)

      if state.error do
        {:halt, state}
      else
        {:cont, state}
      end
    else
      {:cont, state}
    end
  end

  defp handle_stream_event(
         {:error, :no_result_submitted},
         %{text: text} = state,
         _installation,
         _slack_channel_id,
         _thread_ts
       )
       when is_binary(text) do
    if String.trim(text) == "" do
      {:halt, %{state | error: :no_result_submitted}}
    else
      Logger.warning(
        "[Slack.RespondToConversation] Stream finished without a submitted result; keeping streamed text"
      )

      {:halt, state}
    end
  end

  defp handle_stream_event({:error, reason}, state, _installation, _slack_channel_id, _thread_ts) do
    {:halt, %{state | error: reason}}
  end

  defp handle_stream_event(
         {:tool_call, _name, _id, _args},
         state,
         _installation,
         _slack,
         _thread
       ),
       do: {:cont, %{state | tool_ran: true}}

  defp handle_stream_event(_event, state, _installation, _slack_channel_id, _thread_ts),
    do: {:cont, state}

  defp finalize_stream_result(%{error: nil} = state, installation, slack_channel_id, thread_ts) do
    state = flush_response(state, installation, slack_channel_id, thread_ts)

    cond do
      state.error != nil ->
        fail_partial_response(state, installation, slack_channel_id, state.error)

      String.trim(state.text) != "" ->
        :ok = stop_response(state, installation, slack_channel_id)
        {:ok, String.trim(state.text)}

      state.tool_ran ->
        post_tool_only_ack(installation, slack_channel_id, thread_ts)

      true ->
        {:error, :empty_response}
    end
  end

  defp finalize_stream_result(
         %{error: reason} = state,
         installation,
         slack_channel_id,
         _thread_ts
       ) do
    fail_partial_response(state, installation, slack_channel_id, reason)
  end

  defp flush_response(state, installation, slack_channel_id, thread_ts) do
    delta = pending_text(state)

    if String.trim(delta) == "" do
      state
    else
      state
      |> do_flush_response(delta, installation, slack_channel_id, thread_ts)
      |> mark_updated()
    end
  end

  defp do_flush_response(%{mode: nil} = state, delta, installation, slack_channel_id, thread_ts) do
    case API.start_stream(installation, %{
           "channel" => slack_channel_id,
           "thread_ts" => thread_ts,
           "markdown_text" => delta
         }) do
      {:ok, %{"ts" => stream_ts}} when is_binary(stream_ts) ->
        %{state | mode: :stream, stream_ts: stream_ts}

      {:ok, response} ->
        Logger.warning(
          "[Slack.RespondToConversation] Slack stream start did not include a timestamp: #{inspect(response)}"
        )

        start_update_fallback(state, installation, slack_channel_id, thread_ts)

      {:error, reason} ->
        Logger.warning(
          "[Slack.RespondToConversation] Slack stream start failed, falling back to message updates: #{inspect(reason)}"
        )

        start_update_fallback(state, installation, slack_channel_id, thread_ts)
    end
  end

  defp do_flush_response(
         %{mode: :stream, stream_ts: stream_ts} = state,
         delta,
         installation,
         slack_channel_id,
         _thread_ts
       ) do
    case API.append_stream(installation, %{
           "channel" => slack_channel_id,
           "ts" => stream_ts,
           "markdown_text" => delta
         }) do
      {:ok, _response} -> state
      {:error, reason} -> %{state | error: reason}
    end
  end

  defp do_flush_response(
         %{mode: :update, reply_ts: reply_ts} = state,
         _delta,
         installation,
         slack_channel_id,
         _thread_ts
       ) do
    case API.update_message(installation, %{
           "channel" => slack_channel_id,
           "ts" => reply_ts,
           "text" => state.text
         }) do
      {:ok, _response} -> state
      {:error, reason} -> %{state | error: reason}
    end
  end

  defp start_update_fallback(state, installation, slack_channel_id, thread_ts) do
    case API.post_message(installation, %{
           "channel" => slack_channel_id,
           "thread_ts" => thread_ts,
           "text" => state.text
         }) do
      {:ok, %{"ts" => reply_ts}} when is_binary(reply_ts) ->
        %{state | mode: :update, reply_ts: reply_ts}

      {:ok, response} ->
        %{state | error: {:missing_reply_ts, response}}

      {:error, reason} ->
        %{state | error: reason}
    end
  end

  defp stop_response(%{mode: :stream, stream_ts: stream_ts}, installation, slack_channel_id)
       when is_binary(stream_ts) do
    stop_stream_with_retry(installation, slack_channel_id, stream_ts, 3)
  end

  defp stop_response(%{mode: :update}, _installation, _slack_channel_id), do: :ok

  # The reply text was already streamed successfully; only the finalizing
  # `chat.stopStream` failed. Retrying the whole Oban job would post a duplicate
  # reply, so retry just the stop call and, if it keeps failing, accept the
  # lingering streaming indicator rather than double-posting.
  defp stop_stream_with_retry(installation, slack_channel_id, stream_ts, attempts_left) do
    case API.stop_stream(installation, %{"channel" => slack_channel_id, "ts" => stream_ts}) do
      {:ok, _response} ->
        :ok

      {:error, reason} when attempts_left > 1 ->
        Logger.warning(
          "[Slack.RespondToConversation] Slack stream stop failed, retrying: #{inspect(reason)}"
        )

        stop_stream_with_retry(installation, slack_channel_id, stream_ts, attempts_left - 1)

      {:error, reason} ->
        Logger.warning(
          "[Slack.RespondToConversation] Slack stream stop failed after retries; reply already delivered: #{inspect(reason)}"
        )

        :ok
    end
  end

  # A mid-stream failure after a message was already made visible: finalize that
  # same message as the failure instead of leaving a truncated partial and
  # posting a second, contradictory failure message. The `{:notified, reason}`
  # signals the caller that the user has already been told.
  defp fail_partial_response(
         %{mode: :stream, stream_ts: stream_ts} = state,
         installation,
         slack_channel_id,
         reason
       )
       when is_binary(stream_ts) do
    _ =
      API.append_stream(installation, %{
        "channel" => slack_channel_id,
        "ts" => stream_ts,
        "markdown_text" => @interrupted_stream_note
      })

    _ = stop_response(state, installation, slack_channel_id)
    {:error, {:notified, reason}}
  end

  defp fail_partial_response(
         %{mode: :update, reply_ts: reply_ts},
         installation,
         slack_channel_id,
         reason
       )
       when is_binary(reply_ts) do
    _ =
      API.update_message(installation, %{
        "channel" => slack_channel_id,
        "ts" => reply_ts,
        "text" => @interrupted_message
      })

    {:error, {:notified, reason}}
  end

  defp fail_partial_response(_state, _installation, _slack_channel_id, reason) do
    {:error, reason}
  end

  defp post_tool_only_ack(installation, slack_channel_id, thread_ts) do
    case API.post_message(installation, %{
           "channel" => slack_channel_id,
           "thread_ts" => thread_ts,
           "text" => @tool_only_ack
         }) do
      {:ok, _response} -> {:ok, @tool_only_ack}
      {:error, reason} -> {:error, reason}
    end
  end

  defp should_update?(%{text: text, last_text: last_text, last_update_ms: last_update_ms}) do
    enough_text? = byte_size(text) - byte_size(last_text) >= @min_update_chars

    enough_time? =
      is_nil(last_update_ms) or
        System.monotonic_time(:millisecond) - last_update_ms >= @update_interval_ms

    enough_text? and enough_time?
  end

  defp pending_text(%{text: text, last_text: last_text}) do
    String.replace_prefix(text, last_text, "")
  end

  defp mark_updated(%{text: text} = state) do
    %{state | last_text: text, last_update_ms: System.monotonic_time(:millisecond)}
  end

  defp initial_stream_state do
    %{
      text: "",
      last_text: "",
      error: nil,
      last_update_ms: nil,
      mode: nil,
      stream_ts: nil,
      reply_ts: nil,
      tool_ran: false
    }
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
      "text" => @no_reply_message
    })
    |> case do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule Hive.Integrations.SlackEvents do
  @moduledoc """
  Handles incoming Slack events and creates signals from monitored channel messages.
  """

  alias Hive.Integrations
  alias Hive.Signals

  require Logger

  def verify_signature(raw_body, timestamp, signature, signing_secret) do
    base_string = "v0:#{timestamp}:#{raw_body}"

    expected =
      "v0=" <>
        (:crypto.mac(:hmac, :sha256, signing_secret, base_string) |> Base.encode16(case: :lower))

    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def handle_event(%{"type" => "message", "subtype" => _subtype}),
    do: :ignored

  def handle_event(
        %{"type" => "message", "channel" => channel_id, "thread_ts" => thread_ts} = event
      )
      when is_binary(thread_ts) do
    case Integrations.find_monitored_channel(channel_id) do
      nil ->
        :ignored

      channel ->
        handle_thread_reply(event, channel)
    end
  end

  def handle_event(%{"type" => "message", "channel" => channel_id} = event) do
    case Integrations.find_monitored_channel(channel_id) do
      nil ->
        :ignored

      channel ->
        handle_new_message(event, channel)
    end
  end

  def handle_event(_event), do: :ignored

  defp handle_new_message(event, channel) do
    timestamp = parse_slack_timestamp(event["ts"])

    attrs = %{
      title: truncate(event["text"], 120),
      body: event["text"],
      source: "slack",
      source_author: resolve_author(channel, event["user"]),
      source_channel: "##{channel.channel_name}",
      source_url: build_message_url(channel.channel_id, event["ts"]),
      source_timestamp: timestamp
    }

    case Signals.create_signal(attrs) do
      {:ok, signal} ->
        Logger.info("Created signal from Slack message in ##{channel.channel_name}")
        {:ok, signal}

      {:error, changeset} ->
        Logger.error("Failed to create signal: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp handle_thread_reply(event, channel) do
    source_url = build_message_url(event["channel"], event["thread_ts"])

    case Signals.get_signal_by_source_url(source_url) do
      nil ->
        Logger.debug("No signal found for thread #{event["thread_ts"]}")
        :ignored

      signal ->
        timestamp = parse_slack_timestamp(event["ts"])

        attrs = %{
          author: resolve_author(channel, event["user"]),
          body: event["text"],
          source_url: build_message_url(event["channel"], event["ts"]),
          source_timestamp: timestamp
        }

        case Signals.add_signal_message(signal, attrs) do
          {:ok, message} ->
            Logger.info("Added thread reply to signal #{signal.id}")
            {:ok, message}

          {:error, changeset} ->
            Logger.error("Failed to add signal message: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end

  defp parse_slack_timestamp(ts) when is_binary(ts) do
    ts
    |> String.split(".")
    |> List.first()
    |> String.to_integer()
    |> DateTime.from_unix!()
  end

  defp parse_slack_timestamp(_), do: DateTime.utc_now()

  defp build_message_url(channel_id, ts) do
    clean_ts = String.replace(ts, ".", "")
    "slack://channel/#{channel_id}/p#{clean_ts}"
  end

  defp truncate(nil, _), do: "New message"

  defp truncate(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp resolve_author(_channel, nil), do: nil

  defp resolve_author(channel, user_id) do
    case slack_api().get_user_display_name(channel.slack_integration, user_id) do
      {:ok, author} ->
        author

      {:error, reason} ->
        Logger.warning("Failed to resolve Slack user #{user_id}: #{inspect(reason)}")
        user_id
    end
  end

  defp slack_api do
    Application.get_env(:hive, :slack_api, Hive.Integrations.SlackAPI)
  end
end

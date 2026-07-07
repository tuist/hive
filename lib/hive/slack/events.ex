defmodule Hive.Slack.Events do
  @moduledoc """
  Dispatches inbound Slack Events API payloads after the controller has
  verified the request signature and resolved the installation.
  """

  require Logger

  alias Hive.Audit
  alias Hive.Slack
  alias Hive.Slack.Installation
  alias Hive.Slack.Workers.RespondToConversation
  alias Hive.Slack.Workers.UnfurlLinks

  @doc """
  Handles a verified Events API envelope for a known installation.

  The controller is responsible for the `url_verification` challenge;
  this function never sees that type.
  """
  def handle(%{"type" => "event_callback", "event" => event}, %Installation{} = installation)
      when is_map(event) do
    handle_event(event, installation)
  end

  def handle(_envelope, %Installation{}), do: :ok

  defp handle_event(%{"type" => "app_mention"} = event, installation) do
    with {:ok, channel} <- ensure_channel(installation, event["channel"]),
         _ = ensure_user(installation, event["user"]),
         {:ok, message} <- persist_message(installation, channel, event) do
      Audit.record("slack.app_mentioned", %{
        target_type: "slack_installation",
        target_id: installation.id,
        target_label: installation.team_name || installation.team_id,
        metadata: %{
          channel_id: channel.id,
          slack_channel_id: channel.slack_channel_id,
          slack_ts: message.slack_ts
        }
      })

      message_ts = event["ts"]
      thread_ts = event["thread_ts"] || message_ts

      _ =
        RespondToConversation.enqueue(installation.id, channel.id, thread_ts,
          message_ts: message_ts
        )

      :ok
    else
      _ -> :ok
    end
  end

  defp handle_event(%{"type" => "message"} = event, installation) do
    if skip_message?(event) do
      :ok
    else
      with {:ok, channel} <- ensure_channel(installation, event["channel"]),
           _ = ensure_user(installation, event["user"]),
           {:ok, _message} <- persist_message(installation, channel, event) do
        :ok
      else
        _ -> :ok
      end
    end
  end

  defp handle_event(%{"type" => "link_shared"} = event, installation) do
    channel = event["channel"]
    message_ts = event["message_ts"]
    urls = event |> Map.get("links", []) |> Enum.map(& &1["url"]) |> Enum.filter(&is_binary/1)

    if is_binary(channel) and is_binary(message_ts) and urls != [] do
      _ = UnfurlLinks.enqueue(installation.id, channel, message_ts, urls)
    end

    :ok
  end

  defp handle_event(event, _installation) do
    Logger.debug(fn -> "[Slack.Events] ignoring event: #{inspect(event["type"])}" end)
    :ok
  end

  defp skip_message?(%{"subtype" => "bot_message"}), do: true
  defp skip_message?(%{"bot_id" => bot_id}) when is_binary(bot_id) and bot_id != "", do: true

  defp skip_message?(%{"subtype" => subtype})
       when subtype in ["message_changed", "message_deleted"], do: true

  defp skip_message?(_event), do: false

  defp ensure_channel(_installation, nil), do: {:error, :missing_channel}

  defp ensure_channel(installation, slack_channel_id) when is_binary(slack_channel_id) do
    Slack.upsert_channel(installation, %{slack_channel_id: slack_channel_id})
  end

  defp ensure_user(_installation, nil), do: :ok

  defp ensure_user(installation, slack_user_id) when is_binary(slack_user_id) do
    case Slack.upsert_user(installation, %{slack_user_id: slack_user_id}) do
      {:ok, _user} -> :ok
      _ -> :ok
    end
  end

  defp persist_message(installation, channel, event) do
    Slack.insert_message(installation, channel, %{
      slack_user_id: event["user"],
      slack_ts: event["ts"],
      thread_ts: event["thread_ts"],
      text: event["text"],
      raw_payload: event
    })
  end
end

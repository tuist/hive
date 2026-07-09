defmodule Hive.Slack.Workers.UnfurlLinks do
  @moduledoc """
  Async unfurl handler for Slack `link_shared` events.

  For each URL Slack reports we ask `Hive.Slack.Unfurler` for a
  payload; if any URL resolves, we batch them into a single
  `chat.unfurl` call. When no URL resolves, we don't call Slack at all
  rather than posting an empty unfurls map.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: 300, states: :incomplete]

  require Logger

  alias Hive.Slack
  alias Hive.Slack.API
  alias Hive.Slack.Installation
  alias Hive.Slack.Unfurler

  def enqueue(installation_id, channel, message_ts, urls, opts \\ [])
      when is_binary(installation_id) and is_binary(channel) and is_binary(message_ts) and
             is_list(urls) do
    urls = Enum.filter(urls, &is_binary/1)

    if urls == [] do
      :skipped
    else
      %{
        "installation_id" => installation_id,
        "channel" => channel,
        "message_ts" => message_ts,
        "urls" => urls
      }
      |> put_optional("source", Keyword.get(opts, :source))
      |> put_optional("unfurl_id", Keyword.get(opts, :unfurl_id))
      |> new()
      |> Oban.insert()
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "installation_id" => installation_id,
            "channel" => channel,
            "message_ts" => message_ts,
            "urls" => urls
          } = args
      }) do
    with %{} = installation <- Slack.get_installation(installation_id),
         true <- Installation.connected?(installation) || {:skipped, :disconnected},
         unfurls when map_size(unfurls) > 0 <- build_unfurls(urls) do
      params =
        args
        |> Map.take(["source", "unfurl_id"])
        |> unfurl_target(channel, message_ts)
        |> Map.put("unfurls", unfurls)

      case API.unfurl(installation, params) do
        {:ok, _} ->
          :ok

        {:error, {:slack_api_error, "missing_scope"} = reason} ->
          Logger.warning(
            "[Slack.UnfurlLinks] chat.unfurl skipped for installation #{installation_id}: #{inspect(reason)}"
          )

          :ok

        {:error, reason} ->
          Logger.warning(
            "[Slack.UnfurlLinks] chat.unfurl failed for installation #{installation_id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    else
      nil ->
        Logger.info("[Slack.UnfurlLinks] installation #{installation_id} no longer exists")
        :ok

      {:skipped, _} ->
        :ok

      unfurls when is_map(unfurls) ->
        :ok
    end
  end

  defp build_unfurls(urls) do
    urls
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn url, acc ->
      case Unfurler.unfurl(url) do
        {:ok, payload} -> Map.put(acc, url, payload)
        :skip -> acc
      end
    end)
  end

  defp put_optional(map, _key, value) when value in [nil, ""], do: map
  defp put_optional(map, key, value) when is_binary(value), do: Map.put(map, key, value)
  defp put_optional(map, _key, _value), do: map

  defp unfurl_target(%{"source" => source, "unfurl_id" => unfurl_id}, _channel, _message_ts)
       when is_binary(source) and is_binary(unfurl_id),
       do: %{"source" => source, "unfurl_id" => unfurl_id}

  defp unfurl_target(_params, channel, message_ts),
    do: %{"channel" => channel, "ts" => message_ts}
end

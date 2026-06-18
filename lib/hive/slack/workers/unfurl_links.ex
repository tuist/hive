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

  def enqueue(installation_id, channel, message_ts, urls)
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
      |> new()
      |> Oban.insert()
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "installation_id" => installation_id,
          "channel" => channel,
          "message_ts" => message_ts,
          "urls" => urls
        }
      }) do
    with %{} = installation <- Slack.get_installation(installation_id),
         true <- Installation.connected?(installation) || {:skipped, :disconnected},
         unfurls when map_size(unfurls) > 0 <- build_unfurls(urls) do
      case API.unfurl(installation, %{
             "channel" => channel,
             "ts" => message_ts,
             "unfurls" => unfurls
           }) do
        {:ok, _} ->
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
end

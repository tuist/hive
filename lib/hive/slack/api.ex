defmodule Hive.Slack.API do
  @moduledoc """
  Thin Req-based wrapper around the Slack Web API endpoints Hive uses.

  Every function takes an `%Installation{}` so it can authenticate as
  that workspace's bot. Disconnected installations short-circuit with
  `{:error, :installation_disconnected}` so callers don't accidentally
  POST to Slack with a revoked token.
  """

  alias Hive.Slack.Installation

  @base_url "https://slack.com/api/"

  @doc """
  Posts a message to a Slack channel via `chat.postMessage`.

  `params` is merged into the JSON body Slack expects, so any
  Block Kit payload (`blocks:`, `attachments:`, `thread_ts:`, etc.) goes
  through unchanged.
  """
  def post_message(installation, params), do: post(installation, "chat.postMessage", params)

  @doc """
  Updates an already-posted message via `chat.update`.
  """
  def update_message(installation, params), do: post(installation, "chat.update", params)

  @doc """
  Starts a native Slack streamed message via `chat.startStream`.
  """
  def start_stream(installation, params), do: post(installation, "chat.startStream", params)

  @doc """
  Appends markdown text to a native Slack streamed message via `chat.appendStream`.
  """
  def append_stream(installation, params), do: post(installation, "chat.appendStream", params)

  @doc """
  Stops a native Slack streamed message via `chat.stopStream`.
  """
  def stop_stream(installation, params), do: post(installation, "chat.stopStream", params)

  @doc """
  Sets Slack's native assistant status for a thread.
  """
  def set_assistant_thread_status(installation, params),
    do: post(installation, "assistant.threads.setStatus", params)

  @doc """
  Attaches unfurl previews to a message via `chat.unfurl`. `params`
  must include `"channel"`, `"ts"`, and an `"unfurls"` map keyed by
  the URLs being unfurled.
  """
  def unfurl(installation, params), do: post(installation, "chat.unfurl", params)

  @doc """
  Fetches a single channel's info via `conversations.info`.
  """
  def get_channel(installation, slack_channel_id) when is_binary(slack_channel_id),
    do: get(installation, "conversations.info", %{"channel" => slack_channel_id})

  @doc """
  Lists messages in a thread via `conversations.replies`.
  """
  def list_thread_messages(installation, channel, thread_ts, opts \\ %{}) do
    params =
      opts
      |> Map.new()
      |> Map.put("channel", channel)
      |> Map.put("ts", thread_ts)

    get(installation, "conversations.replies", params)
  end

  @doc """
  Fetches a Slack user's info via `users.info`.
  """
  def get_user(installation, slack_user_id) when is_binary(slack_user_id),
    do: get(installation, "users.info", %{"user" => slack_user_id})

  @doc """
  Posts to a Slack `response_url` returned by an interaction payload.
  These URLs are signed Slack callbacks and don't need the bot token.
  """
  def post_response(response_url, body) when is_binary(response_url) and is_map(body) do
    case Req.post(response_url,
           headers: [{"content-type", "application/json"}],
           json: body
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        {:error, {:slack_response_http, status}}

      {:error, reason} ->
        {:error, {:slack_response_transport, reason}}
    end
  end

  defp post(%Installation{} = installation, action, params) do
    with {:ok, token} <- token_for(installation),
         {:ok, body} <- request(:post, action, token, json: params) do
      decode(body)
    end
  end

  defp get(%Installation{} = installation, action, params) do
    with {:ok, token} <- token_for(installation),
         {:ok, body} <- request(:get, action, token, params: params) do
      decode(body)
    end
  end

  defp token_for(installation) do
    if Installation.connected?(installation) do
      {:ok, installation.bot_token}
    else
      {:error, :installation_disconnected}
    end
  end

  defp request(method, action, token, opts) do
    url = @base_url <> action
    headers = [{"authorization", "Bearer " <> token}]

    request_opts =
      opts
      |> Keyword.put_new(:headers, [])
      |> Keyword.update!(:headers, &(&1 ++ headers))

    case do_request(method, url, request_opts) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:slack_api_http, status}}
      {:error, reason} -> {:error, {:slack_api_transport, reason}}
    end
  end

  defp do_request(:post, url, opts), do: Req.post(url, opts)
  defp do_request(:get, url, opts), do: Req.get(url, opts)

  defp decode(%{"ok" => true} = body), do: {:ok, body}
  defp decode(%{"ok" => false, "error" => error}), do: {:error, {:slack_api_error, error}}
  defp decode(body) when is_binary(body), do: {:error, {:slack_api_unexpected, body}}
  defp decode(body), do: {:error, {:slack_api_unexpected, body}}
end

defmodule Hive.Slack.Signature do
  @moduledoc """
  Verifies signatures on Events API and Interactivity requests from Slack.

  Slack signs each request with HMAC-SHA256 over
  `"v0:" <> timestamp <> ":" <> raw_body`, using the app-wide signing
  secret, and sends the result as `X-Slack-Signature: v0=<hex>`. A
  5-minute timestamp window protects against replay.
  """

  @signature_prefix "v0="
  @replay_window_seconds 300

  def secret do
    :hive
    |> Application.get_env(:slack, [])
    |> Keyword.get(:signing_secret)
    |> case do
      secret when is_binary(secret) ->
        secret = String.trim(secret)
        if secret == "", do: {:error, :not_configured}, else: {:ok, secret}

      _other ->
        {:error, :not_configured}
    end
  end

  @doc """
  Verifies a Slack request given the raw body, the `X-Slack-Signature`
  header value, the `X-Slack-Request-Timestamp` header value, and the
  signing secret.
  """
  def verify(raw_body, signature, timestamp, secret, now \\ System.system_time(:second))

  def verify(raw_body, signature, timestamp, secret, now)
      when is_binary(raw_body) and is_binary(signature) and is_binary(timestamp) and
             is_binary(secret) do
    with {:ok, ts} <- parse_timestamp(timestamp),
         :ok <- check_freshness(ts, now),
         {:ok, digest} <- parse_signature(signature),
         expected <- compute(raw_body, ts, secret),
         true <- Plug.Crypto.secure_compare(expected, digest) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_signature}
    end
  end

  def verify(_raw_body, _signature, _timestamp, _secret, _now),
    do: {:error, :invalid_signature}

  defp parse_timestamp(value) do
    case Integer.parse(value) do
      {ts, ""} -> {:ok, ts}
      _ -> {:error, :invalid_timestamp}
    end
  end

  defp check_freshness(ts, now) when abs(now - ts) <= @replay_window_seconds, do: :ok
  defp check_freshness(_ts, _now), do: {:error, :expired_timestamp}

  defp parse_signature(@signature_prefix <> hex) do
    hex = String.downcase(hex)

    if String.match?(hex, ~r/\A[0-9a-f]{64}\z/) do
      {:ok, hex}
    else
      {:error, :invalid_signature}
    end
  end

  defp parse_signature(_other), do: {:error, :invalid_signature}

  defp compute(raw_body, ts, secret) do
    base = "v0:" <> Integer.to_string(ts) <> ":" <> raw_body
    :hmac |> :crypto.mac(:sha256, secret, base) |> Base.encode16(case: :lower)
  end
end

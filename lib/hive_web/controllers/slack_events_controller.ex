defmodule HiveWeb.SlackEventsController do
  use HiveWeb, :controller

  alias Hive.Integrations
  alias Hive.Integrations.SlackEvents

  require Logger

  def handle(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def handle(conn, %{"type" => "event_callback", "event" => event}) do
    raw_body = conn.private[:raw_body]
    timestamp = get_req_header(conn, "x-slack-request-timestamp") |> List.first()
    signature = get_req_header(conn, "x-slack-signature") |> List.first()

    with :ok <- verify_timestamp(timestamp),
         {:ok, signing_secret} <- find_signing_secret(),
         :ok <- SlackEvents.verify_signature(raw_body, timestamp, signature, signing_secret) do
      SlackEvents.handle_event(event)
      json(conn, %{ok: true})
    else
      {:error, :stale_timestamp} ->
        conn |> put_status(:unauthorized) |> json(%{error: "stale timestamp"})

      {:error, :no_signing_secret} ->
        Logger.warning("Slack event received but no integration has a signing secret configured")
        conn |> put_status(:unauthorized) |> json(%{error: "not configured"})

      {:error, :invalid_signature} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid signature"})
    end
  end

  def handle(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "unknown event type"})
  end

  defp verify_timestamp(nil), do: {:error, :stale_timestamp}

  defp verify_timestamp(timestamp) do
    case Integer.parse(timestamp) do
      {ts, _} ->
        now = System.system_time(:second)

        if abs(now - ts) < 300 do
          :ok
        else
          {:error, :stale_timestamp}
        end

      :error ->
        {:error, :stale_timestamp}
    end
  end

  defp find_signing_secret do
    case Integrations.list_all_slack_integrations_with_signing_secret() do
      [integration | _] -> {:ok, integration.signing_secret}
      [] -> {:error, :no_signing_secret}
    end
  end
end

defmodule HiveWeb.GitHubEventsController do
  use HiveWeb, :controller

  alias Hive.Integrations
  alias Hive.Integrations.GitHubEvents

  require Logger

  def handle(conn, _params) do
    raw_body = conn.private[:raw_body]
    event_type = get_req_header(conn, "x-github-event") |> List.first()
    signature = get_req_header(conn, "x-hub-signature-256") |> List.first()

    with {:ok, webhook_secret} <- find_webhook_secret(),
         :ok <- GitHubEvents.verify_signature(raw_body, signature, webhook_secret) do
      Task.start(fn -> GitHubEvents.handle_event(event_type, conn.body_params) end)
      json(conn, %{ok: true})
    else
      {:error, :no_webhook_secret} ->
        Logger.warning("GitHub event received but no app has a webhook secret configured")
        conn |> put_status(:unauthorized) |> json(%{error: "not configured"})

      {:error, :invalid_signature} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid signature"})
    end
  end

  defp find_webhook_secret do
    case Integrations.list_github_apps() do
      [app | _] -> {:ok, app.webhook_secret}
      [] -> {:error, :no_webhook_secret}
    end
  end
end

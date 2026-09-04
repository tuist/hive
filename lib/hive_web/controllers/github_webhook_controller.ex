defmodule HiveWeb.GitHubWebhookController do
  use HiveWeb, :controller

  alias Hive.GitHub.Webhooks

  def create(conn, _params) do
    raw_body = Map.get(conn.private, :hive_raw_body, "")
    signature = conn |> get_req_header("x-hub-signature-256") |> List.first()
    event = conn |> get_req_header("x-github-event") |> List.first()

    with {:ok, secret} <- Webhooks.secret(),
         :ok <- Webhooks.verify_signature(raw_body, signature, secret) do
      case Webhooks.handle_event(event, conn.body_params) do
        :ok -> send_resp(conn, :accepted, "")
        {:error, _reason} -> send_resp(conn, :internal_server_error, "")
      end
    else
      {:error, :not_configured} -> send_resp(conn, :service_unavailable, "")
      {:error, _reason} -> send_resp(conn, :unauthorized, "")
    end
  end
end

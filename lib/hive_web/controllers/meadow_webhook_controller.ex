defmodule HiveWeb.MeadowWebhookController do
  @moduledoc """
  Inbound webhook for meadow-scoped sources (currently Grafana).

  The URL carries the meadow id, the source key, and a per-webhook
  token: `/webhooks/meadows/:meadow_id/:source/:token`. The token is
  hashed and compared in constant time before the payload is parsed and
  upserted into forage.
  """

  use HiveWeb, :controller

  alias Hive.Meadows
  alias Hive.Meadows.Webhook
  alias Hive.Meadows.Webhooks
  alias Hive.Repo

  def create(conn, %{"meadow_id" => meadow_id, "source" => source, "token" => token}) do
    with {:ok, source_atom} <- parse_source(source),
         {:ok, meadow} <- fetch_meadow(meadow_id),
         %Webhook{} = webhook <- Webhooks.find_by_token(meadow.id, source_atom, token),
         {:ok, _alerts} <- ingest(source_atom, meadow, webhook, conn.body_params) do
      Webhooks.touch_last_used(webhook)
      send_resp(conn, :accepted, "")
    else
      {:error, :invalid_payload} -> send_resp(conn, :unprocessable_entity, "")
      {:error, :not_found} -> send_resp(conn, :not_found, "")
      _ -> send_resp(conn, :unauthorized, "")
    end
  end

  defp parse_source(source) when is_binary(source) do
    case Enum.find(Webhook.sources(), &(Atom.to_string(&1) == source)) do
      nil -> {:error, :unknown_source}
      atom -> {:ok, atom}
    end
  end

  defp fetch_meadow(id) do
    case Repo.get(Meadows.Meadow, id) do
      nil -> {:error, :not_found}
      meadow -> {:ok, meadow}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp ingest(source, meadow, webhook, payload),
    do: Meadows.ingest_webhook(source, meadow, webhook, payload)
end

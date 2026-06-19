defmodule HiveWeb.DomainWebhookController do
  @moduledoc """
  Inbound webhook for domain-scoped sources (currently Grafana).

  The URL carries the domain id, the source key, and a per-webhook
  token: `/webhooks/domains/:domain_id/:source/:token`. The token is
  hashed and compared in constant time before the payload is parsed and
  upserted into forage.
  """

  use HiveWeb, :controller

  alias Hive.Domains
  alias Hive.Domains.Webhook
  alias Hive.Domains.Webhooks
  alias Hive.Repo

  def create(conn, %{"domain_id" => domain_id, "source" => source, "token" => token}) do
    with {:ok, source_atom} <- parse_source(source),
         {:ok, domain} <- fetch_domain(domain_id),
         %Webhook{} = webhook <- Webhooks.find_by_token(domain.id, source_atom, token),
         {:ok, _alerts} <- ingest(source_atom, domain, webhook, conn.body_params) do
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

  defp fetch_domain(id) do
    case Repo.get(Domains.Domain, id) do
      nil -> {:error, :not_found}
      domain -> {:ok, domain}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp ingest(source, domain, webhook, payload),
    do: Domains.ingest_webhook(source, domain, webhook, payload)
end

defmodule HiveWeb.ProductWebhookController do
  @moduledoc """
  Inbound webhook for product-scoped sources (currently Grafana).

  The URL carries the product id, the source key, and a per-webhook
  token: `/webhooks/products/:product_id/:source/:token`. The token is
  hashed and compared in constant time before the payload is parsed and
  upserted into forage.
  """

  use HiveWeb, :controller

  alias Hive.Forage.Grafana
  alias Hive.Products
  alias Hive.Products.Webhook
  alias Hive.Products.Webhooks
  alias Hive.Repo

  def create(conn, %{"product_id" => product_id, "source" => source, "token" => token}) do
    with {:ok, source_atom} <- parse_source(source),
         {:ok, product} <- fetch_product(product_id),
         %Webhook{} = webhook <- Webhooks.find_by_token(product.id, source_atom, token),
         {:ok, _alerts} <- ingest(source_atom, product, webhook, conn.body_params) do
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

  defp fetch_product(id) do
    case Repo.get(Products.Product, id) do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp ingest(:grafana, product, webhook, payload), do: Grafana.ingest(product, webhook, payload)
end

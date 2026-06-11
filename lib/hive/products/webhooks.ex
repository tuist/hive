defmodule Hive.Products.Webhooks do
  @moduledoc """
  Manages inbound webhooks attached to a product. Tokens are generated
  once on creation: the plaintext is returned to the caller (shown once
  in the UI), only the SHA-256 hash is persisted, and verification
  hashes the URL-supplied token and looks it up by hash.
  """

  import Ecto.Query

  alias Hive.Products.Product
  alias Hive.Products.Webhook
  alias Hive.Repo

  @token_bytes 32
  @token_prefix "hwh_"

  def list_for_product(%Product{id: product_id}), do: list_for_product(product_id)

  def list_for_product(product_id) when is_binary(product_id) do
    Webhook
    |> where([webhook], webhook.product_id == ^product_id)
    |> order_by([webhook], desc: webhook.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a webhook for `product`. Returns `{:ok, {webhook, token}}` where
  `token` is the plaintext token that should be displayed once and never
  stored. On invalid attrs returns `{:error, changeset}`.
  """
  def create(%Product{} = product, attrs) do
    token = generate_token()
    hash = hash_token(token)

    attrs =
      attrs
      |> normalize_attrs()
      |> Map.put(:product_id, product.id)
      |> Map.put(:token_hash, hash)

    %Webhook{}
    |> Webhook.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, webhook} -> {:ok, {webhook, token}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def delete(%Webhook{} = webhook), do: Repo.delete(webhook)

  @doc """
  Finds a webhook matching the URL-supplied token, restricted to the
  given product and source. Returns the webhook or `nil`.

  The lookup is by hash (constant cost in DB); the equality comparison
  on `token_hash` is then done in constant time to avoid leaking timing
  signal even if two distinct tokens collide on a prefix.
  """
  def find_by_token(product_id, source, token)
      when is_binary(product_id) and is_atom(source) and is_binary(token) do
    hash = hash_token(token)

    Webhook
    |> where([webhook], webhook.product_id == ^product_id and webhook.source == ^source)
    |> Repo.all()
    |> Enum.find(fn webhook -> Plug.Crypto.secure_compare(webhook.token_hash, hash) end)
  end

  def find_by_token(_product_id, _source, _token), do: nil

  def touch_last_used(%Webhook{} = webhook) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    webhook
    |> Ecto.Changeset.change(last_used_at: now)
    |> Repo.update()
  end

  defp generate_token do
    @token_prefix <>
      (@token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false))
  end

  defp hash_token(token) do
    :sha256
    |> :crypto.hash(token)
    |> Base.encode16(case: :lower)
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
    |> Map.update(:source, nil, &cast_source/1)
  end

  defp cast_source(value) when is_atom(value), do: value

  defp cast_source(value) when is_binary(value) do
    case Enum.find(Webhook.sources(), &(Atom.to_string(&1) == value)) do
      nil -> value
      source -> source
    end
  end

  defp cast_source(value), do: value
end

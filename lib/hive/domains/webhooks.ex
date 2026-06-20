defmodule Hive.Domains.Webhooks do
  @moduledoc """
  Manages inbound webhooks attached to a domain. Tokens are generated
  once on creation: the plaintext is returned to the caller (shown once
  in the UI), only the SHA-256 hash is persisted, and verification
  hashes the URL-supplied token and looks it up by hash.
  """

  import Ecto.Query

  alias Hive.Domains.Domain
  alias Hive.Domains.Webhook
  alias Hive.Repo

  @token_bytes 32
  @token_prefix "hwh_"
  @attr_key_map %{
    "name" => :name,
    "source" => :source
  }
  @attr_keys Map.values(@attr_key_map)

  def list_for_domain(%Domain{id: domain_id}), do: list_for_domain(domain_id)

  def list_for_domain(domain_id) when is_binary(domain_id) do
    Webhook
    |> where([webhook], webhook.domain_id == ^domain_id)
    |> order_by([webhook], desc: webhook.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a webhook for `domain`. Returns `{:ok, {webhook, token}}` where
  `token` is the plaintext token that should be displayed once and never
  stored. On invalid attrs returns `{:error, changeset}`.
  """
  def create(%Domain{} = domain, attrs) do
    token = generate_token()
    hash = hash_token(token)

    attrs =
      attrs
      |> normalize_attrs()
      |> Map.put(:domain_id, domain.id)
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
  given domain and source. Returns the webhook or `nil`.

  Lookup is a single indexed query: `token_hash` carries a unique index,
  and the WHERE clause also pins `domain_id` and `source` so a token
  belonging to a different domain or source can never resolve. Since
  matching happens inside the database, there is no Elixir-level
  iteration whose timing could leak which row (if any) matched.
  """
  def find_by_token(domain_id, source, token)
      when is_binary(domain_id) and is_atom(source) and is_binary(token) do
    hash = hash_token(token)
    Repo.get_by(Webhook, token_hash: hash, domain_id: domain_id, source: source)
  end

  def find_by_token(_domain_id, _source, _token), do: nil

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
    attrs
    |> Enum.reduce(%{}, &put_known_attr/2)
    |> Map.update(:source, nil, &cast_source/1)
  end

  defp put_known_attr({key, value}, acc) when is_binary(key) do
    case Map.fetch(@attr_key_map, key) do
      {:ok, attr} -> Map.put(acc, attr, value)
      :error -> acc
    end
  end

  defp put_known_attr({key, value}, acc) when key in @attr_keys, do: Map.put(acc, key, value)
  defp put_known_attr(_entry, acc), do: acc

  defp cast_source(value) when is_atom(value), do: value

  defp cast_source(value) when is_binary(value) do
    case Enum.find(Webhook.sources(), &(Atom.to_string(&1) == value)) do
      nil -> value
      source -> source
    end
  end

  defp cast_source(value), do: value
end

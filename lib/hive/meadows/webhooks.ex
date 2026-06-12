defmodule Hive.Meadows.Webhooks do
  @moduledoc """
  Manages inbound webhooks attached to a meadow. Tokens are generated
  once on creation: the plaintext is returned to the caller (shown once
  in the UI), only the SHA-256 hash is persisted, and verification
  hashes the URL-supplied token and looks it up by hash.
  """

  import Ecto.Query

  alias Hive.Meadows.Meadow
  alias Hive.Meadows.Webhook
  alias Hive.Repo

  @token_bytes 32
  @token_prefix "hwh_"

  def list_for_meadow(%Meadow{id: meadow_id}), do: list_for_meadow(meadow_id)

  def list_for_meadow(meadow_id) when is_binary(meadow_id) do
    Webhook
    |> where([webhook], webhook.meadow_id == ^meadow_id)
    |> order_by([webhook], desc: webhook.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a webhook for `meadow`. Returns `{:ok, {webhook, token}}` where
  `token` is the plaintext token that should be displayed once and never
  stored. On invalid attrs returns `{:error, changeset}`.
  """
  def create(%Meadow{} = meadow, attrs) do
    token = generate_token()
    hash = hash_token(token)

    attrs =
      attrs
      |> normalize_attrs()
      |> Map.put(:meadow_id, meadow.id)
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
  given meadow and source. Returns the webhook or `nil`.

  Lookup is a single indexed query: `token_hash` carries a unique index,
  and the WHERE clause also pins `meadow_id` and `source` so a token
  belonging to a different meadow or source can never resolve. Since
  matching happens inside the database, there is no Elixir-level
  iteration whose timing could leak which row (if any) matched.
  """
  def find_by_token(meadow_id, source, token)
      when is_binary(meadow_id) and is_atom(source) and is_binary(token) do
    hash = hash_token(token)
    Repo.get_by(Webhook, token_hash: hash, meadow_id: meadow_id, source: source)
  end

  def find_by_token(_meadow_id, _source, _token), do: nil

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

defmodule Hive.Domains.Webhook do
  @moduledoc """
  Per-domain inbound webhook for an external source (Grafana, etc).

  The plaintext token is generated once when the webhook is created,
  shown to the user, and never stored. Only its SHA-256 hash lives in
  the database. Lookup at ingest time hashes the URL-supplied token and
  matches it against `token_hash`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources [:grafana]

  schema "domain_webhooks" do
    field :name, :string
    field :source, Ecto.Enum, values: @sources
    field :token_hash, :string
    field :last_used_at, :utc_datetime

    belongs_to :domain, Hive.Domains.Domain

    timestamps(type: :utc_datetime)
  end

  def sources, do: @sources

  def source_label(:grafana), do: "Grafana"

  @doc false
  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:name, :source, :token_hash, :domain_id])
    |> validate_required([:name, :source, :token_hash, :domain_id])
    |> validate_length(:name, max: 120)
    |> validate_inclusion(:source, @sources)
    |> unique_constraint(:token_hash)
  end
end

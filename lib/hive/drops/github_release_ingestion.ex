defmodule Hive.Drops.GitHubReleaseIngestion do
  @moduledoc """
  Tracks GitHub releases that have already been evaluated for drop items.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses [:generated, :ignored]
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "drop_github_release_ingestions" do
    field :release_key, :string
    field :release_key_hash, :string
    field :release_fingerprint, :string
    field :status, Ecto.Enum, values: @statuses
    field :items_count, :integer
    field :processed_at, :utc_datetime

    belongs_to :github_repository, Hive.Domains.GitHubRepository

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(ingestion, attrs) do
    ingestion
    |> cast(attrs, [
      :github_repository_id,
      :release_key,
      :release_key_hash,
      :release_fingerprint,
      :status,
      :items_count,
      :processed_at
    ])
    |> validate_required([
      :github_repository_id,
      :release_key,
      :release_key_hash,
      :release_fingerprint,
      :status,
      :items_count,
      :processed_at
    ])
    |> validate_length(:release_key_hash, is: 64)
    |> validate_length(:release_fingerprint, is: 64)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:items_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:github_repository_id)
    |> unique_constraint([:github_repository_id, :release_key_hash],
      name: :drop_release_ingestions_repo_key_index
    )
  end
end

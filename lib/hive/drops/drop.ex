defmodule Hive.Drops.Drop do
  @moduledoc """
  A shipped-update entry. Sourced from either a user-facing item
  generated from a connected repository's GitHub release, or from an
  operator-registered RSS/Atom feed. Each drop is associated to zero or
  more meadows through
  `Hive.Drops.DropMeadow`; the classifier populates that association.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @source_types [:github_release, :rss]
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "drops" do
    field :source_type, Ecto.Enum, values: @source_types
    field :external_id, :string
    field :title, :string
    field :body, :string
    field :url, :string
    field :version, :string
    field :published_at, :utc_datetime
    field :classified_at, :utc_datetime

    belongs_to :drop_source, Hive.Drops.DropSource
    belongs_to :github_repository, Hive.Meadows.GitHubRepository

    many_to_many :meadows, Hive.Meadows.Meadow,
      join_through: Hive.Drops.DropMeadow,
      join_keys: [drop_id: :id, meadow_id: :id]

    timestamps(type: :utc_datetime)
  end

  def source_types, do: @source_types

  def changeset(drop, attrs) do
    drop
    |> cast(attrs, [
      :source_type,
      :external_id,
      :title,
      :body,
      :url,
      :version,
      :published_at,
      :classified_at,
      :drop_source_id,
      :github_repository_id
    ])
    |> validate_required([:source_type, :external_id, :title, :url])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_length(:title, max: 500)
    |> validate_length(:url, max: 2000)
    |> validate_length(:external_id, max: 500)
    |> validate_length(:version, max: 80)
    |> unique_constraint([:source_type, :external_id],
      name: :drops_source_type_external_id_index
    )
  end
end

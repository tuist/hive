defmodule Hive.Meadows.MeadowRepository do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "meadows_github_repositories" do
    belongs_to :meadow, Hive.Meadows.Meadow, primary_key: true
    belongs_to :github_repository, Hive.Meadows.GitHubRepository, primary_key: true

    timestamps(type: :utc_datetime)
  end

  def changeset(meadow_repository, attrs) do
    meadow_repository
    |> cast(attrs, [:meadow_id, :github_repository_id])
    |> validate_required([:meadow_id, :github_repository_id])
    |> unique_constraint([:meadow_id, :github_repository_id],
      name: :meadows_github_repositories_unique_index
    )
  end
end

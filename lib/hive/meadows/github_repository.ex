defmodule Hive.Meadows.GitHubRepository do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @visibilities [:public, :private]

  schema "github_repositories" do
    field :owner, :string
    field :name, :string
    field :visibility, Ecto.Enum, values: @visibilities, default: :public

    many_to_many :meadows, Hive.Meadows.Meadow,
      join_through: Hive.Meadows.MeadowRepository,
      join_keys: [github_repository_id: :id, meadow_id: :id]

    timestamps(type: :utc_datetime)
  end

  def visibilities, do: @visibilities

  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [:owner, :name, :visibility])
    |> normalize_string(:owner)
    |> normalize_string(:name)
    |> validate_required([:owner, :name, :visibility])
    |> validate_length(:owner, max: 39)
    |> validate_length(:name, max: 100)
    |> validate_format(:owner, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/,
      message: "must be a valid GitHub owner"
    )
    |> validate_format(:name, ~r/^[a-z0-9._-]+$/,
      message: "must be a valid GitHub repository name"
    )
    |> validate_inclusion(:visibility, @visibilities)
    |> unique_constraint([:owner, :name])
  end

  def full_name(repository), do: "#{repository.owner}/#{repository.name}"

  defp normalize_string(changeset, field) do
    update_change(changeset, field, fn
      value when is_binary(value) ->
        value
        |> String.trim()
        |> String.downcase()

      value ->
        value
    end)
  end
end

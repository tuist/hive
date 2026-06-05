defmodule Hive.Products.GitHubRepository do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "github_repositories" do
    field :owner, :string
    field :name, :string

    many_to_many :products, Hive.Products.Product,
      join_through: Hive.Products.ProductRepository,
      join_keys: [github_repository_id: :id, product_id: :id]

    timestamps(type: :utc_datetime)
  end

  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [:owner, :name])
    |> normalize_string(:owner)
    |> normalize_string(:name)
    |> validate_required([:owner, :name])
    |> validate_length(:owner, max: 39)
    |> validate_length(:name, max: 100)
    |> validate_format(:owner, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/,
      message: "must be a valid GitHub owner"
    )
    |> validate_format(:name, ~r/^[a-z0-9._-]+$/,
      message: "must be a valid GitHub repository name"
    )
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

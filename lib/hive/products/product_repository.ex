defmodule Hive.Products.ProductRepository do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "products_github_repositories" do
    belongs_to :product, Hive.Products.Product, primary_key: true
    belongs_to :github_repository, Hive.Products.GitHubRepository, primary_key: true

    timestamps(type: :utc_datetime)
  end

  def changeset(product_repository, attrs) do
    product_repository
    |> cast(attrs, [:product_id, :github_repository_id])
    |> validate_required([:product_id, :github_repository_id])
    |> unique_constraint([:product_id, :github_repository_id],
      name: :products_github_repositories_unique_index
    )
  end
end

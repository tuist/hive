defmodule Hive.Products do
  @moduledoc """
  Configures the products managed by this Hive instance.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Hive.Products.GitHubRepository
  alias Hive.Products.Product
  alias Hive.Products.ProductRepository
  alias Hive.Repo

  def list_products do
    Product
    |> order_by([product], asc: product.name)
    |> preload(:github_repositories)
    |> Repo.all()
  end

  def change_product(product \\ %Product{}, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  def create_product(attrs) do
    changeset = change_product(%Product{}, attrs)

    if changeset.valid? do
      changeset
      |> create_product_multi(Product.repository_attrs(changeset))
      |> Repo.transaction()
      |> case do
        {:ok, %{product: product}} ->
          {:ok, Repo.preload(product, :github_repositories)}

        {:error, :product, changeset, _changes} ->
          {:error, changeset}

        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp create_product_multi(product_changeset, nil) do
    Multi.insert(Multi.new(), :product, product_changeset)
  end

  defp create_product_multi(product_changeset, repository_attrs) do
    Multi.new()
    |> Multi.insert(:product, product_changeset)
    |> Multi.run(:github_repository, fn repo, _changes ->
      get_or_create_github_repository(repo, repository_attrs)
    end)
    |> Multi.insert(:product_repository, fn %{product: product, github_repository: repository} ->
      ProductRepository.changeset(%ProductRepository{}, %{
        product_id: product.id,
        github_repository_id: repository.id
      })
    end)
  end

  defp get_or_create_github_repository(repo, attrs) do
    case repo.get_by(GitHubRepository, owner: attrs.owner, name: attrs.name) do
      %GitHubRepository{} = repository ->
        {:ok, repository}

      nil ->
        %GitHubRepository{}
        |> GitHubRepository.changeset(attrs)
        |> repo.insert()
    end
  end
end

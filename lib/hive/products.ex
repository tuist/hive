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

  def get_product!(id) do
    Product
    |> preload(:github_repositories)
    |> Repo.get!(id)
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

  def update_product(%Product{} = product, attrs) do
    product = Repo.preload(product, :github_repositories)
    changeset = change_product(product, attrs)
    repository_fields_present? = repository_fields_present?(attrs)
    repository_attrs = Product.repository_attrs(changeset)

    if changeset.valid? do
      changeset
      |> update_product_multi(product, repository_attrs, repository_fields_present?)
      |> Repo.transaction()
      |> case do
        {:ok, %{product: product}} ->
          {:ok, Repo.preload(product, :github_repositories, force: true)}

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

  defp update_product_multi(
         product_changeset,
         product,
         repository_attrs,
         repository_fields_present?
       ) do
    Multi.new()
    |> Multi.update(:product, product_changeset)
    |> maybe_replace_product_repository(product, repository_attrs, repository_fields_present?)
  end

  defp maybe_replace_product_repository(multi, _product, _repository_attrs, false), do: multi

  defp maybe_replace_product_repository(multi, product, nil, true) do
    Multi.delete_all(multi, :product_repositories, product_repositories_query(product.id))
  end

  defp maybe_replace_product_repository(multi, product, repository_attrs, true) do
    multi
    |> Multi.run(:github_repository, fn repo, _changes ->
      get_or_create_github_repository(repo, repository_attrs)
    end)
    |> Multi.delete_all(:product_repositories, product_repositories_query(product.id))
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

  defp product_repositories_query(product_id) do
    from(product_repository in ProductRepository,
      where: product_repository.product_id == ^product_id
    )
  end

  defp repository_fields_present?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, "github_repository_owner") or
      Map.has_key?(attrs, :github_repository_owner) or
      Map.has_key?(attrs, "github_repository_name") or
      Map.has_key?(attrs, :github_repository_name)
  end

  defp repository_fields_present?(_attrs), do: false
end

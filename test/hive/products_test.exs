defmodule Hive.ProductsTest do
  use Hive.DataCase, async: true

  alias Hive.Products
  alias Hive.Products.GitHubRepository
  alias Hive.Products.Product
  alias Hive.Products.ProductRepository

  describe "change_product/2" do
    test "is valid with a name" do
      changeset = Products.change_product(%Product{}, %{name: "Hive"})

      assert changeset.valid?
    end

    test "requires a name" do
      changeset = Products.change_product(%Product{}, %{})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:name]
    end

    test "requires repository owner and name together" do
      owner_changeset =
        Products.change_product(%Product{}, %{
          name: "Hive",
          github_repository_owner: "tuist"
        })

      name_changeset =
        Products.change_product(%Product{}, %{
          name: "Hive",
          github_repository_name: "hive"
        })

      refute owner_changeset.valid?
      refute name_changeset.valid?
      assert {"can't be blank", _} = owner_changeset.errors[:github_repository_name]
      assert {"can't be blank", _} = name_changeset.errors[:github_repository_owner]
    end

    test "normalizes GitHub repository fields" do
      changeset =
        Products.change_product(%Product{}, %{
          name: "Hive",
          github_repository_owner: " Tuist ",
          github_repository_name: " Hive "
        })

      assert get_change(changeset, :github_repository_owner) == "tuist"
      assert get_change(changeset, :github_repository_name) == "hive"
    end
  end

  describe "create_product/1" do
    test "creates a product without a repository" do
      assert {:ok, product} = Products.create_product(%{name: "Hive"})

      assert product.name == "Hive"
      assert product.github_repositories == []
    end

    test "creates a product with a GitHub repository" do
      assert {:ok, product} =
               Products.create_product(%{
                 name: "Hive",
                 description: "Product orchestration",
                 github_repository_owner: "Tuist",
                 github_repository_name: "Hive"
               })

      assert product.description == "Product orchestration"
      assert [%GitHubRepository{owner: "tuist", name: "hive"}] = product.github_repositories
      assert Repo.aggregate(ProductRepository, :count) == 1
    end

    test "allows several products to share one repository" do
      assert {:ok, _} =
               Products.create_product(%{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "monorepo"
               })

      assert {:ok, _} =
               Products.create_product(%{
                 name: "Forge",
                 github_repository_owner: "tuist",
                 github_repository_name: "monorepo"
               })

      assert Repo.aggregate(GitHubRepository, :count) == 1
      assert Repo.aggregate(ProductRepository, :count) == 2
    end

    test "rejects duplicate product names" do
      assert {:ok, _} = Products.create_product(%{name: "Hive"})

      assert {:error, changeset} = Products.create_product(%{name: "Hive"})

      assert {"has already been taken", _} = changeset.errors[:name]
    end

    test "returns a changeset for invalid repository fields" do
      assert {:error, changeset} =
               Products.create_product(%{
                 name: "Hive",
                 github_repository_owner: "-tuist",
                 github_repository_name: "hive"
               })

      assert {"must be a valid GitHub owner", _} = changeset.errors[:github_repository_owner]
      assert Repo.aggregate(Product, :count) == 0
    end
  end

  describe "list_products/0" do
    test "returns products ordered by name with repositories preloaded" do
      assert {:ok, _} =
               Products.create_product(%{
                 name: "Forge",
                 github_repository_owner: "tuist",
                 github_repository_name: "forge"
               })

      assert {:ok, _} = Products.create_product(%{name: "Atlas"})

      assert [atlas, forge] = Products.list_products()
      assert atlas.name == "Atlas"
      assert forge.name == "Forge"
      assert [%GitHubRepository{name: "forge"}] = forge.github_repositories
    end
  end
end

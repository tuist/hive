defmodule HiveWeb.SettingsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Hive.GitHub.Repositories
  alias Hive.Products
  alias Hive.Products.GitHubRepository
  alias Hive.Products.Product
  alias HiveWeb.SettingsComponents

  describe "products/1" do
    defp assigns(overrides \\ %{}) do
      Map.merge(
        %{
          form: to_form(Products.change_product(), as: :product),
          products: [],
          repository_query: "",
          repository_options: [],
          repository_search_error: nil,
          selected_repository: nil
        },
        overrides
      )
    end

    test "renders the empty state and add product action" do
      assigns = assigns()

      html =
        rendered_to_string(~H"""
        <SettingsComponents.products
          products={@products}
          form={@form}
          repository_query={@repository_query}
          repository_options={@repository_options}
          repository_search_error={@repository_search_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ "Add product"
      assert html =~ "No products configured"
      assert html =~ ~s(class="noora-card")
      assert html =~ ~s(id="products-table")
      assert html =~ ~s(id="new-product-modal")
    end

    test "renders the new product modal with repository options" do
      assigns =
        assigns(%{
          repository_query: "tuist",
          repository_options: [
            %Repositories{owner: "tuist", name: "hive", description: "Product orchestration"}
          ],
          selected_repository: %Repositories{
            owner: "tuist",
            name: "hive",
            description: "Product orchestration"
          }
        })

      html =
        rendered_to_string(~H"""
        <SettingsComponents.products
          products={@products}
          form={@form}
          repository_query={@repository_query}
          repository_options={@repository_options}
          repository_search_error={@repository_search_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ ~s(id="new-product-modal")
      assert html =~ "New product"
      assert html =~ "GitHub repository"
      assert html =~ "tuist/hive"
      assert html =~ ~s(class="noora-dropdown")
      assert html =~ ~s(name="product[github_repository_owner]" value="tuist")
      assert html =~ ~s(name="product[github_repository_name]" value="hive")
      assert html =~ ~s(phx-submit="save")
    end

    test "renders configured products and repositories" do
      product = %Product{
        name: "Hive",
        description: "Product orchestration",
        github_repositories: [%GitHubRepository{owner: "tuist", name: "hive"}]
      }

      assigns = assigns(%{products: [product]})

      html =
        rendered_to_string(~H"""
        <SettingsComponents.products
          products={@products}
          form={@form}
          repository_query={@repository_query}
          repository_options={@repository_options}
          repository_search_error={@repository_search_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ "Hive"
      assert html =~ "Product orchestration"
      assert html =~ "tuist/hive"
      assert html =~ ~s(data-type="badge")
      assert html =~ ~s(data-part="repository-cell")
    end
  end
end

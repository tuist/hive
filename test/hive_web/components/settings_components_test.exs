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
          repository_options: [],
          repository_load_error: nil,
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
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
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
          repository_options: [
            %Repositories{owner: "tuist", name: "sdk", description: "Tuist SDK for Apple apps"},
            %Repositories{owner: "tuist", name: "Grafana", description: "Monitoring dashboards"},
            %Repositories{owner: "tuist", name: "AXe", description: "Simulator accessibility"}
          ],
          selected_repository: nil
        })

      html =
        rendered_to_string(~H"""
        <SettingsComponents.products
          products={@products}
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ ~s(id="new-product-modal")
      assert html =~ "New product"
      assert html =~ "Visibility"
      assert html =~ "GitHub repository"
      assert html =~ "tuist/AXe"
      assert html =~ "tuist/Grafana"
      assert html =~ "tuist/sdk"
      assert repository_position(html, "tuist/AXe") < repository_position(html, "tuist/Grafana")
      assert repository_position(html, "tuist/Grafana") < repository_position(html, "tuist/sdk")
      assert html =~ ~s(data-label="tuist/Grafana Monitoring dashboards")
      assert html =~ ~s(class="noora-dropdown")
      assert html =~ ~s(id="new-product-visibility")
      assert html =~ ~s(name="product[visibility]")
      assert html =~ ~s(name="product[github_repository_owner]")
      assert html =~ ~s(name="product[github_repository_name]")
      assert html =~ ~s(phx-submit="save")
    end

    test "renders configured products and repositories" do
      product = %Product{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
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
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ "Hive"
      assert html =~ "Product orchestration"
      assert html =~ "Public"
      assert html =~ "tuist/hive"
      assert html =~ ~s(href="/settings/products/#{product.id}")
      assert html =~ ~s(data-type="badge")
      assert html =~ ~s(data-part="repository-cell")
    end

    test "renders a product detail form" do
      product = %Product{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Atlas",
        description: "Internal planning.",
        visibility: :private,
        github_repositories: []
      }

      assigns =
        assigns(%{
          product: product,
          form: to_form(Products.change_product(product), as: :product)
        })

      html =
        rendered_to_string(~H"""
        <SettingsComponents.product_detail
          product={@product}
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ "Atlas"
      assert html =~ "Internal planning."
      assert html =~ "Save product"
      assert html =~ ~s(class="noora-dropdown")
      assert html =~ ~s(id="product-visibility")
      assert html =~ ~s(name="product[visibility]")
      refute html =~ "Linked specs"
      refute html =~ "Back"
    end
  end

  defp repository_position(html, repository) do
    {position, _length} = :binary.match(html, repository)
    position
  end
end

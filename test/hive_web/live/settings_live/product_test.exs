defmodule HiveWeb.SettingsLive.ProductTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias Hive.Products

  test "redirects guests to login", %{conn: conn} do
    {:ok, product} = Products.create_product(%{name: "Hive"})

    assert {:error, {:redirect, %{to: "/login"}}} =
             live(conn, ~p"/settings/products/#{product.id}")
  end

  test "redirects signed-in contributors", %{conn: conn} do
    {conn, user} = sign_in(conn, "contributor@example.com")
    {:ok, product} = Products.create_product(%{name: "Hive"})

    Mimic.stub(Auth, :member?, fn ^user -> false end)

    assert {:error, {:redirect, %{to: "/login"}}} =
             live(conn, ~p"/settings/products/#{product.id}")
  end

  test "renders a product detail page for signed-in members", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, product} =
      Products.create_product(%{
        name: "Hive",
        description: "Product orchestration",
        visibility: "private",
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    {:ok, _view, html} = live(conn, ~p"/settings/products/#{product.id}")

    assert html =~ "Hive"
    assert html =~ "Product orchestration"
    assert html =~ "Private"
    assert html =~ "tuist/hive"
    assert html =~ "Save product"
  end

  test "updates product fields", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    {:ok, product} = Products.create_product(%{name: "Atlas"})

    {:ok, view, _html} = live(conn, ~p"/settings/products/#{product.id}")

    html =
      view
      |> form("form[data-part='form']",
        product: %{
          name: "Atlas",
          description: "Private planning.",
          visibility: "private",
          github_repository_owner: "",
          github_repository_name: ""
        }
      )
      |> render_submit()

    assert html =~ "Private planning."
    assert html =~ "Private"
  end

  test "searches and replaces the product repository", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, product} =
      Products.create_product(%{
        name: "Hive",
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    Mimic.stub(Repositories, :search_accessible_repositories, fn "tuist" ->
      {:ok, [%Repositories{owner: "tuist", name: "tuist", description: "Tuist monorepo"}]}
    end)

    {:ok, view, _html} = live(conn, ~p"/settings/products/#{product.id}")
    Mimic.allow(Repositories, self(), view.pid)

    assert render_keyup(view, "search_repositories", %{"value" => "tuist"}) =~ "tuist/tuist"

    assert render_click(view, "select_repository", %{
             "owner" => "tuist",
             "name" => "tuist",
             "description" => "Tuist monorepo"
           }) =~ "tuist/tuist"

    html =
      view
      |> form("form[data-part='form']",
        product: %{
          name: "Hive",
          visibility: "public",
          github_repository_owner: "tuist",
          github_repository_name: "tuist"
        }
      )
      |> render_submit()

    assert html =~ "tuist/tuist"
  end

  test "creates a webhook from the modal form", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    {:ok, product} = Products.create_product(%{name: "Hive"})

    {:ok, view, _html} = live(conn, ~p"/settings/products/#{product.id}")

    html =
      render_submit(view, "create_webhook", %{
        "webhook" => %{"name" => "Grafana prod", "source" => "grafana"}
      })

    assert html =~ "Grafana prod"
    assert html =~ "Webhook URL"
    assert [_webhook] = Hive.Products.Webhooks.list_for_product(product)
  end

  test "deletes a webhook", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    {:ok, product} = Products.create_product(%{name: "Hive"})

    {:ok, {webhook, _}} =
      Hive.Products.Webhooks.create(product, %{"name" => "G", "source" => "grafana"})

    {:ok, view, _html} = live(conn, ~p"/settings/products/#{product.id}")

    render_click(view, "delete_webhook", %{"id" => webhook.id})

    assert Hive.Products.Webhooks.list_for_product(product) == []
  end
end

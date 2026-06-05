defmodule HiveWeb.SettingsLive.ProductsTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.GitHub.Repositories

  test "redirects guests to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/settings/products")
  end

  test "renders the products settings page for signed-in users", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, _view, html} = live(conn, ~p"/settings/products")

    assert html =~ "Products"
    assert html =~ "Add product"
    assert html =~ "No products configured"
  end

  test "renders the new product modal", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, _view, html} = live(conn, ~p"/settings/products")

    assert html =~ ~s(id="new-product-modal")
    assert html =~ "New product"
    assert html =~ "GitHub repository"
  end

  test "searches GitHub repositories and creates a product from the selected repository", %{
    conn: conn
  } do
    {conn, _user} = sign_in(conn, "alice@example.com")

    Mimic.stub(Repositories, :search_accessible_repositories, fn "tuist" ->
      {:ok, [%Repositories{owner: "tuist", name: "hive", description: "Product orchestration"}]}
    end)

    {:ok, view, _html} = live(conn, ~p"/settings/products")
    Mimic.allow(Repositories, self(), view.pid)

    assert render_keyup(view, "search_repositories", %{"value" => "tuist"}) =~ "tuist/hive"

    assert render_click(view, "select_repository", %{
             "owner" => "tuist",
             "name" => "hive",
             "description" => "Product orchestration"
           }) =~ "tuist/hive"

    html =
      render_submit(view, "save", %{
        "product" => %{
          "name" => "Hive",
          "description" => "Product orchestration",
          "github_repository_owner" => "tuist",
          "github_repository_name" => "hive"
        }
      })

    assert html =~ "Hive"
    assert html =~ "Product orchestration"
    assert html =~ "tuist/hive"
  end

  test "surfaces validation errors with interpolated bindings", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, _html} = live(conn, ~p"/settings/products")

    html =
      render_submit(view, "save", %{
        "product" => %{"name" => String.duplicate("a", 121)}
      })

    assert html =~ "should be at most 120 character(s)"
    refute html =~ "%{count}"
  end
end

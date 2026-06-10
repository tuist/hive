defmodule HiveWeb.SettingsLive.ProductsTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts
  alias Hive.Auth
  alias HiveWeb.SettingsLive.Products

  test "redirects guests to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/settings/products")
  end

  test "redirects signed-in contributors" do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "contributor@example.com",
        provider: "test",
        provider_uid: "contributor"
      })

    Mimic.stub(Auth, :member?, fn ^user -> false end)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        signed_in?: true,
        current_user: user,
        product_name: "Hive",
        flash: %{}
      }
    }

    assert {:ok, socket} = Products.mount(%{}, %{}, socket)
    assert {:redirect, %{to: "/login"}} = socket.redirected
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
    assert html =~ "Visibility"
    assert html =~ "GitHub repository"
  end

  test "creates a product from the selected repository", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, _html} = live(conn, ~p"/settings/products")

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
          "visibility" => "private",
          "github_repository_owner" => "tuist",
          "github_repository_name" => "hive"
        }
      })

    assert html =~ "Hive"
    assert html =~ "Product orchestration"
    assert html =~ "Private"
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

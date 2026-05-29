defmodule HiveWeb.AuthControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Auth

  test "GET / redirects to login when the instance is private", %{conn: conn} do
    stub(Auth, :private?, fn -> true end)
    stub(Auth, :current_user, fn _conn -> nil end)

    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/login"
  end

  test "GET /login renders a button per configured provider", %{conn: conn} do
    stub(Auth, :private?, fn -> true end)

    stub(Auth, :providers, fn ->
      [
        google: %{display_name: "Google", allowed_domains: []},
        oidc: %{display_name: "Example IDP", allowed_domains: []}
      ]
    end)

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "Log in to Hive"
    assert response =~ "Continue with Google"
    assert response =~ "Continue with Example IDP"
    assert response =~ ~s|href="/auth/google"|
    assert response =~ ~s|href="/auth/oidc"|
  end

  test "GET /login warns when no provider is configured but instance is private", %{conn: conn} do
    stub(Auth, :private?, fn -> true end)
    stub(Auth, :providers, fn -> [] end)

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "No identity provider is configured"
  end

  test "GET /login on a public instance shows provider buttons when configured", %{conn: conn} do
    stub(Auth, :private?, fn -> false end)

    stub(Auth, :providers, fn ->
      [google: %{display_name: "Google", allowed_domains: []}]
    end)

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "Continue with Google"
    assert response =~ "Continue without signing in"
  end

  test "GET /login on a public instance with no providers shows the public-instance copy", %{
    conn: conn
  } do
    stub(Auth, :private?, fn -> false end)
    stub(Auth, :providers, fn -> [] end)

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "This instance is public"
    refute response =~ "HIVE_AUTH_MODE"
  end
end

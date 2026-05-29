defmodule HiveWeb.AuthControllerTest do
  use HiveWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:hive, :auth)

    on_exit(fn ->
      Application.put_env(:hive, :auth, previous)
    end)
  end

  test "GET / redirects to login when the instance is private", %{conn: conn} do
    Application.put_env(:hive, :auth, visibility: "private")

    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/login"
  end

  test "GET /login renders a button per configured provider", %{conn: conn} do
    Application.put_env(:hive, :auth,
      visibility: "private",
      providers: [
        google: %{display_name: "Google", allowed_domains: []},
        oidc: %{display_name: "Example IDP", allowed_domains: []}
      ]
    )

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "Log in to Hive"
    assert response =~ "Continue with Google"
    assert response =~ "Continue with Example IDP"
    assert response =~ ~s|href="/auth/google"|
    assert response =~ ~s|href="/auth/oidc"|
  end

  test "GET /login warns when no provider is configured but instance is private", %{conn: conn} do
    Application.put_env(:hive, :auth, visibility: "private", providers: [])

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "No identity provider is configured"
  end
end

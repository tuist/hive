defmodule HiveWeb.AuthControllerTest do
  use HiveWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:hive, :auth)

    on_exit(fn ->
      Application.put_env(:hive, :auth, previous)
    end)
  end

  test "GET / redirects to login when OIDC auth is enabled", %{conn: conn} do
    Application.put_env(:hive, :auth, mode: "oidc")

    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/login"
  end

  test "GET /login renders generic provider copy", %{conn: conn} do
    Application.put_env(:hive, :auth,
      mode: "oidc",
      provider_name: "Example IDP",
      product_name: "Hive",
      product_tagline: "Product work orchestration"
    )

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "Log in to Hive"
    assert response =~ "Product work orchestration"
    assert response =~ "Continue with Example IDP"
  end
end

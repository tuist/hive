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
      product_tagline: "Product work orchestration",
      oidc_client_id: "client-id",
      oidc_authorize_url: "https://example.com/authorize",
      oidc_token_url: "https://example.com/token"
    )

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "Log in to Hive"
    assert response =~ "Product work orchestration"
    assert response =~ "Continue with Example IDP"
  end

  test "GET /login renders a Google button when Google credentials are configured", %{conn: conn} do
    Application.put_env(:hive, :auth,
      mode: "oidc",
      product_name: "Hive",
      google_client_id: "google-client-id",
      google_client_secret: "google-client-secret"
    )

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "Continue with Google"
  end

  test "GET /auth/google adds hd hint when a single allowed domain is configured", %{conn: conn} do
    Application.put_env(:hive, :auth,
      mode: "oidc",
      google_client_id: "google-client-id",
      google_client_secret: "google-client-secret",
      google_allowed_domains: "tuist.dev"
    )

    conn = get(conn, ~p"/auth/google")

    location = List.first(get_resp_header(conn, "location"))
    assert location =~ "hd=tuist.dev"
  end

  test "GET /auth/google omits hd hint when multiple domains are configured", %{conn: conn} do
    Application.put_env(:hive, :auth,
      mode: "oidc",
      google_client_id: "google-client-id",
      google_client_secret: "google-client-secret",
      google_allowed_domains: "tuist.dev, tuist.io"
    )

    conn = get(conn, ~p"/auth/google")

    location = List.first(get_resp_header(conn, "location"))
    refute location =~ "hd="
  end
end

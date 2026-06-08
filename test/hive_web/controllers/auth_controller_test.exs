defmodule HiveWeb.AuthControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Accounts
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
    assert response =~ ~s|property="og:image"|
    assert response =~ ~s|name="twitter:card" content="summary_large_image"|
    assert response =~ "Continue with Google"
    assert response =~ "Continue with Example IDP"
    assert response =~ ~s|href="/auth/google"|
    assert response =~ ~s|href="/auth/oidc"|
  end

  test "GET /login renders a GitHub button when GitHub is configured", %{conn: conn} do
    stub(Auth, :private?, fn -> true end)

    stub(Auth, :providers, fn ->
      [github: %{display_name: "GitHub", allowed_domains: []}]
    end)

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "Continue with GitHub"
    assert response =~ ~s|href="/auth/github"|
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

  test "GET /login offers a test-user sign in when dev routes are enabled", %{conn: conn} do
    stub(Auth, :private?, fn -> false end)

    stub(Auth, :providers, fn ->
      [
        google: %{display_name: "Google", allowed_domains: []},
        github: %{display_name: "GitHub", allowed_domains: []}
      ]
    end)

    conn = get(conn, ~p"/login")

    response = html_response(conn, 200)
    assert response =~ "Sign in as test user"
    assert response =~ "Continue with Google"
    assert response =~ "Continue with GitHub"
    refute response =~ "Sign in as Google + GitHub user"
    refute response =~ "Sign in as GitHub-only user"
    assert response =~ ~s|action="/dev/login"|
  end

  test "POST /dev/login signs in a test user and redirects to the dashboard", %{conn: conn} do
    conn = post(conn, ~p"/dev/login")

    assert redirected_to(conn) == ~p"/"

    user_id = get_session(conn, :user_id)
    assert user_id

    user = Accounts.get_user(user_id)
    assert user.email == "test@hive.dev"
  end

  test "POST /dev/login ignores requested personas", %{conn: conn} do
    {:ok, _user} =
      Accounts.upsert_from_auth(%{
        email: "maya@example.com",
        provider: "google",
        provider_uid: "google-maya-example"
      })

    conn = post(conn, ~p"/dev/login", %{"email" => "maya@example.com"})

    assert redirected_to(conn) == ~p"/"

    user_id = get_session(conn, :user_id)
    user = Accounts.get_user(user_id)
    assert user.email == "test@hive.dev"
  end

  test "POST /dev/login redirects to the stored return path", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{user_return_to: "/oauth2/authorize?client_id=client"})
      |> post(~p"/dev/login")

    assert redirected_to(conn) == "/oauth2/authorize?client_id=client"
    refute get_session(conn, :user_return_to)
  end
end

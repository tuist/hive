defmodule HiveWeb.AuthControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Accounts.UserIdentity
  alias Hive.Auth
  alias Hive.Repo

  defmodule RedirectStrategy do
    use Ueberauth.Strategy, ignores_csrf_attack: true

    import Phoenix.Controller, only: [redirect: 2]

    def handle_request!(conn) do
      conn
      |> redirect(external: "https://github.example.test/login/oauth/authorize")
      |> halt()
    end
  end

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
    assert response =~ ~s|name="description"|
    assert response =~ ~s|rel="canonical" href="#{HiveWeb.Endpoint.url()}/login"|
    assert response =~ ~s|name="robots" content="noindex, follow"|
    assert response =~ ~s|property="og:image"|
    assert response =~ ~s|name="twitter:card" content="summary_large_image"|
    assert response =~ "Continue with Google"
    assert response =~ "Continue with Example IDP"
    assert response =~ ~s|href="/auth/google"|
    assert response =~ ~s|href="/auth/oidc"|
  end

  test "GET /login stores a local return path for the next sign in", %{conn: conn} do
    stub(Auth, :private?, fn -> true end)

    stub(Auth, :providers, fn ->
      [github: %{display_name: "GitHub", allowed_domains: []}]
    end)

    conn = get(conn, ~p"/login?return_to=/ops/slack")

    assert html_response(conn, 200) =~ "Continue with GitHub"
    assert get_session(conn, :user_return_to) == "/ops/slack"
  end

  test "GET /login ignores external return paths", %{conn: conn} do
    stub(Auth, :private?, fn -> true end)
    stub(Auth, :providers, fn -> [] end)

    conn = get(conn, ~p"/login?return_to=https://example.com")

    assert html_response(conn, 200) =~ "No identity provider is configured"
    refute get_session(conn, :user_return_to)
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
    assert user.role == :admin
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

  test "POST /logout redirects to the submitted local return path", %{conn: conn} do
    {conn, _user} = sign_in(conn, "logout-return@example.com")

    conn = post(conn, ~p"/logout", %{"return_to" => "/projects?page=2"})

    assert redirected_to(conn) == "/projects?page=2"
  end

  test "POST /logout ignores external return paths", %{conn: conn} do
    {conn, _user} = sign_in(conn, "logout-external-return@example.com")

    conn = post(conn, ~p"/logout", %{"return_to" => "https://example.com"})

    assert redirected_to(conn) == ~p"/login"
  end

  test "GET /auth/:provider falls back to starting a configured provider", %{conn: conn} do
    stub(Auth, :provider, fn :github ->
      %{display_name: "GitHub", allowed_domains: []}
    end)

    stub(Auth, :ueberauth_provider, fn :github ->
      {RedirectStrategy, []}
    end)

    conn = HiveWeb.AuthController.request(conn, %{"provider" => "github"})

    assert redirected_to(conn) == "https://github.example.test/login/oauth/authorize"
    assert conn.halted
  end

  test "GET /auth/:provider/callback links the provider to the signed-in user", %{conn: conn} do
    {conn, user} = sign_in(conn, "link-provider-user@example.com")

    stub(Auth, :provider, fn :github ->
      %{display_name: "GitHub", allowed_domains: []}
    end)

    stub(Auth, :check_domain, fn _provider, _email -> :ok end)

    conn =
      conn
      |> Phoenix.Controller.fetch_flash([])
      |> assign_ueberauth("github", "link-provider-gh", "private-github-email@example.com")
      |> HiveWeb.AuthController.callback(%{"provider" => "github"})

    assert redirected_to(conn) == ~p"/account/identities"
    assert get_session(conn, :user_id) == user.id
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "GitHub is connected to your account."

    assert %UserIdentity{user_id: user_id} =
             Repo.get_by(UserIdentity, provider: "github", provider_uid: "link-provider-gh")

    assert user_id == user.id
  end

  test "GET /auth/:provider/callback signs in the linked user when GitHub has no email", %{
    conn: conn
  } do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "linked-google-owner@example.com",
        provider: "google",
        provider_uid: "linked-google-owner"
      })

    assert {:ok, _user} =
             Accounts.link_identity(user, %{
               provider: "github",
               provider_uid: "linked-github-owner"
             })

    stub(Auth, :provider, fn :github ->
      %{display_name: "GitHub", allowed_domains: []}
    end)

    stub(Auth, :check_domain, fn _provider, "" -> :ok end)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> assign_ueberauth("github", "linked-github-owner", nil)
      |> HiveWeb.AuthController.callback(%{"provider" => "github"})

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_id) == user.id
  end

  test "GET /auth/:provider/callback does not move another user's identity", %{conn: conn} do
    {:ok, owner} =
      Accounts.upsert_from_auth(%{
        email: "identity-owner@example.com",
        provider: "github",
        provider_uid: "identity-owner-gh"
      })

    {conn, user} = sign_in(conn, "identity-candidate@example.com")

    stub(Auth, :provider, fn :github ->
      %{display_name: "GitHub", allowed_domains: []}
    end)

    stub(Auth, :check_domain, fn _provider, _email -> :ok end)

    conn =
      conn
      |> Phoenix.Controller.fetch_flash([])
      |> assign_ueberauth("github", "identity-owner-gh", "identity-candidate@example.com")
      |> HiveWeb.AuthController.callback(%{"provider" => "github"})

    assert redirected_to(conn) == ~p"/account/identities"
    assert get_session(conn, :user_id) == user.id

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "GitHub is already connected to another account."

    assert %UserIdentity{user_id: owner_id} =
             Repo.get_by(UserIdentity, provider: "github", provider_uid: "identity-owner-gh")

    assert owner_id == owner.id
  end

  defp assign_ueberauth(conn, _provider, uid, email) do
    auth = %Ueberauth.Auth{uid: uid, info: %Ueberauth.Auth.Info{email: email}}

    assign(conn, :ueberauth_auth, auth)
  end
end

defmodule HiveWeb.AccountLive.IdentitiesTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Repo
  alias Hive.Slack.Installation
  alias Hive.Slack.User, as: SlackUser
  alias HiveWeb.AccountLive.Identities

  test "redirects guests to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/account/identities")
  end

  test "renders connected identities and available providers", %{conn: conn} do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "alice@example.com",
        provider: "google",
        provider_uid: "g-1"
      })

    {:ok, _user} =
      Accounts.upsert_from_auth(%{
        email: user.email,
        provider: "github",
        provider_uid: "gh-9"
      })

    Mimic.stub(Auth, :providers, fn ->
      [
        google: %{display_name: "Google", allowed_domains: []},
        github: %{display_name: "GitHub", allowed_domains: []}
      ]
    end)

    conn = Plug.Test.init_test_session(conn, user_id: user.id)

    {:ok, _view, html} = live(conn, ~p"/account/identities")

    assert html =~ "Identities"
    assert html =~ "Manage the sign-in providers connected to alice@example.com."
    assert html =~ "Google"
    assert html =~ "GitHub"
    assert html =~ "g-1"
    assert html =~ "gh-9"
    refute html =~ "Connect Google"
    refute html =~ "Connect GitHub"
  end

  test "links to configured providers that are not connected", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    Mimic.stub(Auth, :providers, fn ->
      [
        google: %{display_name: "Google", allowed_domains: []},
        github: %{display_name: "GitHub", allowed_domains: []}
      ]
    end)

    Mimic.stub(Hive.Slack, :enabled?, fn -> true end)

    {:ok, _view, html} = live(conn, ~p"/account/identities")

    assert html =~ "Google"
    assert html =~ "Connect GitHub"
    assert html =~ ~s(href="/auth/github")
    assert html =~ "Connect Slack profile"
    assert html =~ ~s(href="/account/slack/new")
  end

  test "renders connected Slack profiles", %{conn: conn} do
    {conn, user} = sign_in(conn, "slack-linked@example.com")

    {:ok, installation} =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T1",
        team_name: "Tuist Workspace",
        bot_token: "xoxb-token",
        installed_at: ~U[2026-06-17 12:00:00Z]
      })
      |> Repo.insert()

    {:ok, _slack_user} =
      %SlackUser{}
      |> SlackUser.changeset(%{
        installation_id: installation.id,
        slack_user_id: "U1",
        email: "different-slack@example.com",
        linked_user_id: user.id
      })
      |> Repo.insert()

    Mimic.stub(Hive.Slack, :enabled?, fn -> true end)

    {:ok, _view, html} = live(conn, ~p"/account/identities")

    assert html =~ "Slack profile"
    assert html =~ "Tuist Workspace"
    assert html =~ "different-slack@example.com"
    assert html =~ "U1"
    assert html =~ "Connected"
  end

  test "shows GitHub as unavailable when its OAuth provider is not configured", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    Mimic.stub(Auth, :providers, fn ->
      [
        google: %{display_name: "Google", allowed_domains: []}
      ]
    end)

    {:ok, _view, html} = live(conn, ~p"/account/identities")

    assert html =~ "GitHub"
    assert html =~ "Not configured"
    assert html =~ "GitHub sign-in is not enabled for this Hive instance"
    refute html =~ ~s(href="/auth/github")
  end

  test "open graph data follows the page contract" do
    data = Identities.open_graph()

    assert data.id == "account-identities"
    assert data.path == "/account/identities"
    assert data.title == "Identities"
    assert length(data.highlights) == 3
  end
end

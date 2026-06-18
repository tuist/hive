defmodule HiveWeb.OpsLive.SlackTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Slack.Installation

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login?return_to=/ops/slack"}}} =
             live(conn, ~p"/ops/slack")
  end

  test "redirects non-admins away from Slack workspace management", %{conn: conn} do
    {conn, user} = sign_in(conn, "member@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :member)

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/ops/slack")
  end

  test "renders Slack workspace management for instance admins", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :admin)

    assert {:ok, _view, html} = live(conn, ~p"/ops/slack")

    assert html =~ "Slack"
    assert html =~ "Workspaces"
    assert html =~ ~s(id="ops-slack")
    assert html =~ ~s(href="/ops/slack")
  end

  test "renders connected workspaces as managed rows", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-slack@example.com")
    {:ok, user} = Accounts.update_user_role(user, :admin)

    installation = %Installation{
      id: Ecto.UUID.generate(),
      team_id: "T1",
      team_name: "Tuist Company",
      installed_at: ~U[2026-06-17 12:00:00Z],
      installed_by_user: user,
      bot_token: "xoxb-token"
    }

    stub(Hive.Slack, :enabled?, fn -> true end)
    stub(Hive.Slack, :list_installations, fn -> [installation] end)

    assert {:ok, _view, html} = live(conn, ~p"/ops/slack")

    assert html =~ ~s(data-part="installation-row")
    assert html =~ "Tuist Company"
    assert html =~ "Connected"
    assert html =~ "Installed by admin-slack@example.com"
    assert html =~ "Installed on 2026-06-17"
    assert html =~ "Disconnect"
    assert html =~ "noora-button"
  end
end

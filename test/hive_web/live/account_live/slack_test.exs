defmodule HiveWeb.AccountLive.SlackTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Slack.Installation

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/account/slack")
  end

  test "redirects collaborators away from Slack workspace management", %{conn: conn} do
    {conn, user} = sign_in(conn, "collaborator@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :collaborator)

    assert {:error, {:redirect, %{to: "/account/identities"}}} = live(conn, ~p"/account/slack")
  end

  test "renders Slack workspace management for organization members", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")

    assert {:ok, _view, html} = live(conn, ~p"/account/slack")

    assert html =~ "Slack"
    assert html =~ "Workspaces"
  end

  test "renders connected workspaces as managed rows", %{conn: conn} do
    {conn, user} = sign_in(conn, "member-slack@example.com")

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

    assert {:ok, _view, html} = live(conn, ~p"/account/slack")

    assert html =~ ~s(data-part="installation-row")
    assert html =~ "Tuist Company"
    assert html =~ "Connected"
    assert html =~ "Installed by member-slack@example.com"
    assert html =~ "Installed on 2026-06-17"
    assert html =~ "Disconnect"
    assert html =~ "noora-button"
  end
end

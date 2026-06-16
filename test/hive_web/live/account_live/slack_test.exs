defmodule HiveWeb.AccountLive.SlackTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts

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
end

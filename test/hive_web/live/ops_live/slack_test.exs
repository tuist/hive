defmodule HiveWeb.OpsLive.SlackTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Repo
  alias Hive.Slack.Installation
  alias Hive.Slack.NotificationRoute

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
    assert html =~ ~s(id="slack-workspaces-table")
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

    assert html =~ ~s(data-part="workspaces-table")
    assert html =~ ~s(id="slack-workspaces-table")
    assert html =~ "Tuist Company"
    assert html =~ "Connected"
    assert html =~ "admin-slack@example.com"
    assert html =~ "Installed on 2026-06-17"
    assert html =~ "Disconnect"
    assert html =~ "Notifications"
    assert html =~ "Specs"
    assert html =~ "Slack channel"
    assert html =~ "Spec review requests"
    assert html =~ "noora-button"
  end

  test "updates Slack notification routes from the workspace row", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-slack-notifications@example.com")
    {:ok, user} = Accounts.update_user_role(user, :admin)

    {:ok, installation} =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T-notify",
        team_name: "Tuist Company",
        installed_at: ~U[2026-06-17 12:00:00Z],
        installed_by_user_id: user.id,
        bot_token: "xoxb-token"
      })
      |> Repo.insert()

    stub(Hive.Slack, :enabled?, fn -> true end)

    assert {:ok, view, _html} = live(conn, ~p"/ops/slack")

    render_submit(view, "save_notification_routes", %{
      "id" => installation.id,
      "installation" => %{
        "notification_routes" => %{
          "specs" => %{"slack_channel_id" => "C123"}
        }
      }
    })

    route =
      Repo.get_by!(NotificationRoute, installation_id: installation.id, object_type: "specs")

    assert route.slack_channel_id == "C123"

    assert route.notification_events == [
             "spec.created",
             "spec.comment.created",
             "spec.review.requested"
           ]
  end
end

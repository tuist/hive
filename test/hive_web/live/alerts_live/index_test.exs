defmodule HiveWeb.AlertsLive.IndexTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Alerts
  alias Hive.Alerts.Rule
  alias Hive.Projects
  alias Hive.Slack.Installation

  setup do
    {:ok, project} = Projects.create_project(%{"name" => "Widgets"})

    installation =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T#{System.unique_integer([:positive])}",
        team_name: "Test workspace",
        bot_user_id: "U0",
        bot_token: "xoxb-test",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Hive.Repo.insert!()

    {:ok, project: project, installation: installation}
  end

  defp promote(user, role) do
    {:ok, user} = Accounts.update_user_role(user, role)
    user
  end

  test "renders empty state for admins with a modal trigger", %{conn: conn, project: project} do
    {conn, user} = sign_in(conn, "admin@example.com")
    _ = promote(user, :admin)

    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/alerts")

    assert html =~ "No alert rules yet"
    assert html =~ "New alert rule"
  end

  test "lists existing rules for admins with a delete button", %{
    conn: conn,
    project: project,
    installation: installation
  } do
    {conn, user} = sign_in(conn, "admin@example.com")
    _ = promote(user, :admin)

    {:ok, _rule} =
      Alerts.create_rule(project, %{
        "name" => "Fresh crashes",
        "trigger" => "new_issue_threshold",
        "threshold_event_count" => 3,
        "threshold_window_minutes" => 60,
        "tier" => "attention",
        "destination_type" => "slack",
        "slack_installation_id" => installation.id,
        "slack_channel_id" => "C99",
        "slack_mention" => "none"
      })

    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/alerts")

    assert html =~ "Fresh crashes"
    assert html =~ "Attention"
    assert html =~ "Delete rule"
  end

  test "admins can create a webhook rule through the modal", %{conn: conn, project: project} do
    {conn, user} = sign_in(conn, "admin@example.com")
    _ = promote(user, :admin)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/alerts")

    render_hook(view, "update_form_name", %{"value" => "Prod regressions"})
    render_hook(view, "update_form_trigger", %{"value" => "regression"})
    render_hook(view, "update_form_tier", %{"value" => "incident"})
    render_hook(view, "update_form_destination", %{"value" => "webhook"})
    render_hook(view, "update_form_webhook_url", %{"value" => "https://example.com/hooks"})
    _html = render_hook(view, "create_rule", %{})

    assert [%Rule{name: "Prod regressions", destination_type: :webhook}] =
             Alerts.list_rules_for_project(project)
  end
end

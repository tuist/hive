defmodule HiveWeb.AlertsLive.IndexTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Alerts
  alias Hive.Alerts.Rule
  alias Hive.Errors.Availability
  alias Hive.Projects
  alias Hive.Slack.Installation

  setup do
    Mimic.stub(Availability, :enabled?, fn -> true end)

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

  test "the former alerts page redirects to the project", %{conn: conn, project: project} do
    assert {:error, {:live_redirect, %{to: path}}} =
             live(conn, ~p"/projects/#{project.id}/alerts")

    assert path == ~p"/projects/#{project.id}"
  end

  test "renders the alert rules table and create action on the project page for administrators",
       %{
         conn: conn,
         project: project
       } do
    {conn, user} = sign_in(conn, "admin@example.com")
    _user = promote(user, :admin)

    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "No alert rules yet"
    assert html =~ "New alert rule"
    refute html =~ "Manage alerts"
  end

  test "lists existing rules with edit and delete actions", %{
    conn: conn,
    project: project,
    installation: installation
  } do
    {conn, user} = sign_in(conn, "admin@example.com")
    _user = promote(user, :admin)
    {:ok, rule} = create_slack_rule(project, installation)

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "Fresh crashes"
    assert html =~ "Attention"
    assert has_element?(view, "#alert-rule-actions-#{rule.id}")
    assert html =~ "Edit"
    assert html =~ "Delete"
  end

  test "administrators can create a webhook rule from the project page", %{
    conn: conn,
    project: project
  } do
    {conn, user} = sign_in(conn, "admin@example.com")
    _user = promote(user, :admin)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    rules = with_target(view, "#project-alert-rules-#{project.id}")

    render_keyup(rules, "update_form_name", %{"value" => "Prod regressions"})
    render_click(rules, "update_form_trigger", %{"value" => "regression"})
    render_click(rules, "update_form_tier", %{"value" => "incident"})
    render_click(rules, "update_form_destination", %{"value" => "webhook"})
    render_keyup(rules, "update_form_webhook_url", %{"value" => "https://example.com/hooks"})
    _html = render_click(rules, "create_rule")

    assert [%Rule{name: "Prod regressions", destination_type: :webhook}] =
             Alerts.list_rules_for_project(project)
  end

  test "administrators can edit an existing rule in a prefilled modal", %{
    conn: conn,
    project: project,
    installation: installation
  } do
    {conn, user} = sign_in(conn, "admin@example.com")
    _user = promote(user, :admin)
    {:ok, rule} = create_slack_rule(project, installation)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    rules = with_target(view, "#project-alert-rules-#{project.id}")

    _html = render_click(rules, "start_edit", %{"id" => rule.id})
    html = render(view)

    assert html =~ ~s(id="edit-alert-rule-modal-name")
    assert html =~ ~s(value="Fresh crashes")
    assert html =~ ~s(id="edit-alert-rule-modal-channel")
    assert html =~ ~s(value="C99")

    render_keyup(rules, "update_form_name", %{"value" => "Production crashes"})
    render_click(rules, "update_form_tier", %{"value" => "incident"})
    _html = render_click(rules, "update_rule")

    assert [%Rule{name: "Production crashes", tier: :incident}] =
             Alerts.list_rules_for_project(project)
  end

  test "members can read rules but cannot manage them", %{
    conn: conn,
    project: project,
    installation: installation
  } do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, rule} = create_slack_rule(project, installation)

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "Fresh crashes"
    refute has_element?(view, "#new-alert-rule")
    refute has_element?(view, "#alert-rule-actions-#{rule.id}")
  end

  defp create_slack_rule(project, installation) do
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
  end
end

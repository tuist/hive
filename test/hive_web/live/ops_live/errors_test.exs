defmodule HiveWeb.OpsLive.ErrorsTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts
  alias Hive.Audit.Activity
  alias Hive.Errors.Summaries
  alias Hive.Errors.SummarySettings
  alias Hive.Repo

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login?return_to=/ops/errors"}}} =
             live(conn, ~p"/ops/errors")
  end

  test "redirects non-admins away from error summary settings", %{conn: conn} do
    {conn, user} = sign_in(conn, "member-error-summary-ops@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :member)

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/ops/errors")
  end

  test "renders runtime error summary settings for admins", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-error-summary-ops@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :admin)

    assert {:ok, _view, html} = live(conn, ~p"/ops/errors")

    assert html =~ ~s(id="ops-error-summaries")
    assert html =~ ~s(id="error-summary-settings-form")
    assert html =~ "Enable error summaries"
    assert html =~ "Schedule"
    assert html =~ "Slack channel identifier"
    assert html =~ "without restarting Hive"
  end

  test "updates settings without restarting Hive", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-error-summary-save@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :admin)
    {:ok, view, _html} = live(conn, ~p"/ops/errors")

    html =
      render_submit(view, "save", %{
        "error_summary_settings" => %{
          "enabled" => "true",
          "schedule" => "15 8 * * 1",
          "slack_channel_id" => "C123"
        }
      })

    assert html =~ "Error summary settings updated."

    assert %SummarySettings{
             enabled: true,
             schedule: "15 8 * * 1",
             slack_channel_id: "C123"
           } = Summaries.settings()

    assert %Activity{interface: "dashboard"} =
             Repo.get_by!(Activity, action: "error_summary_settings.updated")
  end

  test "validates the schedule and required channel", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-error-summary-validation@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :admin)
    {:ok, view, _html} = live(conn, ~p"/ops/errors")

    html =
      render_change(view, "validate", %{
        "error_summary_settings" => %{
          "enabled" => "true",
          "schedule" => "whenever",
          "slack_channel_id" => ""
        }
      })

    assert html =~ "must be a valid five-field Cron schedule"
    assert html =~ "can&#39;t be blank"
  end
end

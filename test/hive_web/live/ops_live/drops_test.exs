defmodule HiveWeb.OpsLive.DropsTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts
  alias Hive.Drops
  alias Hive.Projects

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login?return_to=/ops/drops"}}} =
             live(conn, ~p"/ops/drops")
  end

  test "redirects non-admins away from drop source management", %{conn: conn} do
    {conn, user} = sign_in(conn, "member@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :member)

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/ops/drops")
  end

  test "renders drop sources in the Noora table pattern", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-drops@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :admin)
    {:ok, project} = Projects.create_project(%{name: "Hive"})

    {:ok, source} =
      Drops.create_drop_source(%{
        "project_id" => project.id,
        "url" => "https://tuist.dev/changelog/rss.xml",
        "label" => "Tuist Changelog"
      })

    {:ok, _source} = Drops.record_source_poll(source, {:error, :timeout})

    assert {:ok, _view, html} = live(conn, ~p"/ops/drops")

    assert html =~ ~s(id="drop-sources-table")
    assert html =~ ~s(class="noora-table")
    assert html =~ "Tuist Changelog"
    assert html =~ "https://tuist.dev/changelog/rss.xml"
    assert html =~ "Enabled"
    assert html =~ "Last poll"
    assert html =~ "timeout"
    assert html =~ ~s(id="drop-source-actions-#{source.id}")
    refute html =~ ~s(data-part="source-row")
  end
end

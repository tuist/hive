defmodule HiveWeb.AuditLiveTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts
  alias Hive.Audit

  test "renders audit activities for admins and filters by interface", %{conn: conn} do
    {conn, _admin} = log_in_admin(conn, "admin@example.com")

    {:ok, _activity} =
      Audit.log("spec.updated", %{
        interface: "dashboard",
        actor_email: "alice@example.com",
        target_type: "spec",
        target_id: "spec-1",
        target_label: "Dashboard Spec"
      })

    {:ok, _activity} =
      Audit.log("domain.created", %{
        interface: "mcp",
        actor_name: "MCP User",
        target_type: "domain",
        target_id: "domain-1",
        target_label: "MCP Domain"
      })

    filter_params = %{"filter_interface_op" => "==", "filter_interface_val" => "mcp"}
    {:ok, view, _html} = live(conn, ~p"/audit?#{filter_params}")

    assert has_element?(view, "#audit")
    assert has_element?(view, "#audit-table")
    assert has_element?(view, ~s(a[data-part="target-link"][href="/domains/domain-1"]))

    view
    |> form("#audit-search-form", search: %{query: "MCP User"})
    |> render_change()

    assert_patch(
      view,
      ~p"/audit?#{Map.put(filter_params, "q", "MCP User")}"
    )
  end

  test "redirects non-admin users away from the audit page", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/audit")
  end

  defp log_in_admin(conn, email) do
    {conn, user} = sign_in(conn, email)
    {:ok, user} = Accounts.update_user_role(user, :admin)
    {conn, user}
  end
end

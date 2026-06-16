defmodule Hive.MCP.Components.Tools.ListAuditActivitiesTest do
  use Hive.MCPToolCase

  alias Hive.Audit
  alias Hive.MCP.Components.Tools.ListAuditActivities

  test "returns activities for an admin user" do
    admin = mcp_user("admin@example.com") |> set_role(:admin)

    {:ok, _activity} =
      Audit.log("spec.created", %{
        interface: "dashboard",
        actor_email: "alice@example.com",
        target_type: "spec",
        target_id: "spec-1"
      })

    response = ListAuditActivities.call(mcp_conn(admin), %{"interface" => "dashboard"})
    data = response_json(response)

    assert is_list(data["activities"])
    assert length(data["activities"]) == 1
    assert hd(data["activities"])["action"] == "spec.created"
    assert data["pagination"]["total_count"] == 1
  end

  test "rejects non-admin users" do
    user = mcp_user("member@example.com")
    response = ListAuditActivities.call(mcp_conn(user), %{})

    assert response_json(response) == %{"error" => "forbidden"}
  end

  defp set_role(user, role) do
    {:ok, user} = Hive.Accounts.update_user_role(user, role)
    user
  end
end

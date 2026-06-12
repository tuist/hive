defmodule Hive.MCP.Tools.AuditToolsTest do
  use Hive.MCPToolCase

  alias Hive.Audit
  alias Hive.MCP.Components.Tools.GetAuditActivity
  alias Hive.MCP.Components.Tools.ListAuditActivities

  describe "list_audit_activities" do
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
  end

  describe "get_audit_activity" do
    test "returns a single activity by id for an admin user" do
      admin = mcp_user("admin@example.com") |> set_role(:admin)

      {:ok, activity} =
        Audit.log("meadow.created", %{
          interface: "mcp",
          target_type: "meadow",
          target_id: "meadow-1"
        })

      response = GetAuditActivity.call(mcp_conn(admin), %{"activity_id" => activity.id})
      data = response_json(response)

      assert data["activity"]["id"] == activity.id
      assert data["activity"]["action"] == "meadow.created"
    end

    test "rejects non-admin users" do
      user = mcp_user("member@example.com")
      response = GetAuditActivity.call(mcp_conn(user), %{"activity_id" => "anything"})

      assert response_json(response) == %{"error" => "forbidden"}
    end

    test "returns not_found for a missing id" do
      admin = mcp_user("admin@example.com") |> set_role(:admin)

      response = GetAuditActivity.call(mcp_conn(admin), %{"activity_id" => Ecto.UUID.generate()})

      assert response_json(response) == %{"error" => "not_found"}
    end
  end

  defp set_role(user, role) do
    {:ok, user} = Hive.Accounts.update_user_role(user, role)
    user
  end
end

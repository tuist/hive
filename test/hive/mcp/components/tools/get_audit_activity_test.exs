defmodule Hive.MCP.Components.Tools.GetAuditActivityTest do
  use Hive.MCPToolCase

  alias Hive.Audit
  alias Hive.MCP.Components.Tools.GetAuditActivity

  test "returns a single activity by id for an admin user" do
    admin = mcp_user("admin@example.com") |> set_role(:admin)

    {:ok, activity} =
      Audit.log("domain.created", %{
        interface: "mcp",
        target_type: "domain",
        target_id: "domain-1"
      })

    response = GetAuditActivity.call(mcp_conn(admin), %{"activity_id" => activity.id})
    data = response_json(response)

    assert data["activity"]["id"] == activity.id
    assert data["activity"]["action"] == "domain.created"
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

  defp set_role(user, role) do
    {:ok, user} = Hive.Accounts.update_user_role(user, role)
    user
  end
end

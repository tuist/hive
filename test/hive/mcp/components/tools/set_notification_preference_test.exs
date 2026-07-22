defmodule Hive.MCP.Components.Tools.SetNotificationPreferenceTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.SetNotificationPreference
  alias Hive.Notifications

  test "enables and disables a global email preference" do
    user = mcp_user()

    response =
      SetNotificationPreference.call(mcp_conn(user), %{
        "topic" => "spec_new",
        "cadence" => "daily"
      })
      |> response_json()

    assert response == %{
             "enabled" => true,
             "topic" => "spec_new",
             "scope_id" => "global",
             "cadence" => "daily"
           }

    assert Notifications.subscribed?(user, :spec_new)

    response =
      SetNotificationPreference.call(mcp_conn(user), %{
        "topic" => "spec_new",
        "cadence" => "off"
      })
      |> response_json()

    assert response["enabled"] == false
    refute Notifications.subscribed?(user, :spec_new)
  end

  test "requires a scope for a resource subscription" do
    user = mcp_user()

    response =
      SetNotificationPreference.call(mcp_conn(user), %{
        "topic" => "spec_updates",
        "cadence" => "immediate"
      })
      |> response_json()

    assert response == %{"error" => "scope_id_required"}
  end
end

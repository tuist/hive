defmodule Hive.MCP.Components.Tools.ListNotificationPreferencesTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.ListNotificationPreferences
  alias Hive.Notifications

  test "lists the authenticated user's subscriptions" do
    user = mcp_user()
    Notifications.subscribe(user, :forage_new_items, cadence: :daily)
    Notifications.follow_spec(user, Ecto.UUID.generate(), cadence: :immediate)

    response = ListNotificationPreferences.call(mcp_conn(user), %{}) |> response_json()

    assert response["subscriptions"] == [
             %{
               "cadence" => "daily",
               "scope_id" => "global",
               "scope_type" => "global",
               "topic" => "forage_new_items"
             },
             %{
               "cadence" => "immediate",
               "scope_id" =>
                 Enum.at(Notifications.list_subscriptions(user, :spec_updates), 0).scope_id,
               "scope_type" => "spec",
               "topic" => "spec_updates"
             }
           ]
  end
end

defmodule Hive.MCP.Components.Tools.ListNotificationPreferences do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_notification_preferences",
    title: "List Notification Preferences",
    schema: %{"type" => "object", "properties" => %{}},
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "subscriptions" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "topic" => %{"type" => "string"},
                "scope_type" => %{"type" => "string"},
                "scope_id" => %{"type" => "string"},
                "cadence" => %{"type" => "string"}
              },
              "required" => ["topic", "scope_type", "scope_id", "cadence"],
              "additionalProperties" => false
            }
          }
        },
        ["subscriptions"]
      )

  alias Hive.Notifications

  @impl EMCP.Tool
  def description, do: "List the authenticated user's Hive email subscriptions."

  @impl EMCP.Tool
  def call(conn, _args) do
    subscriptions =
      conn.assigns.current_user
      |> Notifications.list_subscriptions()
      |> Enum.map(fn subscription ->
        %{
          topic: Atom.to_string(subscription.topic),
          scope_type: Atom.to_string(subscription.scope_type),
          scope_id: subscription.scope_id,
          cadence: Atom.to_string(subscription.cadence)
        }
      end)

    json_response(%{subscriptions: subscriptions})
  end
end

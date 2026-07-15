defmodule Hive.MCP.Components.Tools.GetAuditActivity do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_audit_activity",
    title: "Get Audit Activity",
    schema: %{
      "type" => "object",
      "required" => ["activity_id"],
      "properties" => %{
        "activity_id" => %{"type" => "string"}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"activity" => Hive.MCP.Components.Schemas.audit_activity()},
        ["activity"]
      )

  alias Hive.Audit
  alias Hive.Audit.Policy

  @impl EMCP.Tool
  def description, do: "Fetch one Hive audit activity by id. Only available to admins."

  @impl EMCP.Tool
  def call(conn, %{"activity_id" => id}) when is_binary(id) do
    user = conn.assigns[:current_user]

    cond do
      not Policy.authorize?(:audit_activity_read, user, nil) ->
        json_response(%{error: "forbidden"})

      activity = Audit.get_activity(id) ->
        json_response(%{activity: Audit.serialize(activity)})

      true ->
        json_response(%{error: "not_found"})
    end
  end

  def call(_conn, _args), do: json_response(%{error: "activity_id is required"})
end

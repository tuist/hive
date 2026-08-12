defmodule Hive.MCP.Components.Tools.ListPostmortemActionItems do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_postmortem_action_items",
    title: "List Postmortem Action Items",
    schema: %{
      "type" => "object",
      "required" => ["postmortem_id"],
      "properties" => %{
        "postmortem_id" => %{
          "type" => "string",
          "description" => "Postmortem identifier, public number, or shared postmortem address."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "action_items" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Schemas.postmortem_action_item()
          }
        },
        ["action_items"]
      )

  alias Hive.MCP.Components.Tools.Postmortems, as: PostmortemTool
  alias Hive.Postmortems

  @impl EMCP.Tool
  def description, do: "List the action items belonging to one visible postmortem."

  @impl EMCP.Tool
  def call(conn, %{"postmortem_id" => postmortem_id}) do
    case Postmortems.fetch_visible_postmortem_by_reference(
           postmortem_id,
           conn.assigns[:current_user]
         ) do
      {:ok, postmortem} ->
        json_response(%{action_items: PostmortemTool.action_items_json(postmortem)})

      {:error, :not_found} ->
        json_response(%{error: "not_found"})
    end
  end
end

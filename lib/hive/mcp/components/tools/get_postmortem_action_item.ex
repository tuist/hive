defmodule Hive.MCP.Components.Tools.GetPostmortemActionItem do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_postmortem_action_item",
    title: "Get Postmortem Action Item",
    schema: %{
      "type" => "object",
      "required" => ["action_item_id"],
      "properties" => %{
        "action_item_id" => %{
          "type" => "string",
          "description" => "Action-item identifier returned with a postmortem."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"action_item" => Hive.MCP.Components.Schemas.postmortem_action_item()},
        ["action_item"]
      )

  alias Hive.MCP.Components.Tools.Postmortems, as: PostmortemTool
  alias Hive.Postmortems

  @impl EMCP.Tool
  def description, do: "Fetch one action item when its postmortem is visible to the caller."

  @impl EMCP.Tool
  def call(conn, %{"action_item_id" => action_item_id}) do
    case Postmortems.fetch_visible_action_item(action_item_id, conn.assigns[:current_user]) do
      {:ok, _postmortem, action_item} ->
        json_response(%{action_item: PostmortemTool.action_item_json(action_item)})

      {:error, :not_found} ->
        json_response(%{error: "not_found"})
    end
  end
end

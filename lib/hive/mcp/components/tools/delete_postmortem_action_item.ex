defmodule Hive.MCP.Components.Tools.DeletePostmortemActionItem do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "delete_postmortem_action_item",
    title: "Delete Postmortem Action Item",
    read_only_hint: false,
    destructive_hint: true,
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
        %{
          "deleted_action_item" => Hive.MCP.Components.Schemas.postmortem_action_item()
        },
        ["deleted_action_item"]
      )

  alias Hive.Auth
  alias Hive.MCP.Components.Tools.Postmortems, as: PostmortemTool
  alias Hive.Postmortems

  @impl EMCP.Tool
  def description, do: "Delete a postmortem action item. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"action_item_id" => action_item_id}) do
    user = conn.assigns[:current_user]

    if Auth.member?(user) do
      delete(user, action_item_id)
    else
      json_response(%{error: "unauthorized"})
    end
  end

  defp delete(user, action_item_id) do
    case Postmortems.fetch_visible_action_item(action_item_id, user) do
      {:ok, postmortem, action_item} ->
        deleted_action_item = PostmortemTool.action_item_json(action_item)

        case Postmortems.delete_action_item(postmortem, action_item, user) do
          {:ok, _action_item} ->
            json_response(%{deleted_action_item: deleted_action_item})

          {:error, :unauthorized} ->
            json_response(%{error: "unauthorized"})
        end

      {:error, :not_found} ->
        json_response(%{error: "not_found"})
    end
  end
end

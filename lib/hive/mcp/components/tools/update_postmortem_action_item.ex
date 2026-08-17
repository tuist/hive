defmodule Hive.MCP.Components.Tools.UpdatePostmortemActionItem do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "update_postmortem_action_item",
    title: "Update Postmortem Action Item",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["action_item_id"],
      "properties" => %{
        "action_item_id" => %{
          "type" => "string",
          "description" => "Action-item identifier returned with a postmortem."
        },
        "title" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "priority" => %{
          "type" => "string",
          "enum" => Enum.map(Hive.Postmortems.ActionItem.priorities(), &Atom.to_string/1),
          "description" => "Urgency of the follow-up work."
        },
        "completed" => %{
          "type" => "boolean",
          "description" => "Whether the follow-up work is complete."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"action_item" => Hive.MCP.Components.Schemas.postmortem_action_item()},
        ["action_item"]
      )

  alias Hive.MCP.Components.Tools.Postmortems, as: PostmortemTool
  alias Hive.MCP.Tool
  alias Hive.Postmortems

  @impl EMCP.Tool
  def description do
    "Update an action item's text or completion state. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, %{"action_item_id" => action_item_id} = args) do
    user = conn.assigns[:current_user]

    case Postmortems.fetch_visible_action_item(action_item_id, user) do
      {:ok, postmortem, action_item} -> update(postmortem, action_item, user, args)
      {:error, :not_found} -> json_response(%{error: "not_found"})
    end
  end

  defp update(postmortem, action_item, user, args) do
    if Postmortems.can_edit?(postmortem, user) do
      with {:ok, action_item} <- update_text(postmortem, action_item, user, args),
           {:ok, action_item} <- update_completion(postmortem, action_item, user, args) do
        json_response(%{action_item: PostmortemTool.action_item_json(action_item)})
      else
        {:error, changeset} ->
          json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
      end
    else
      json_response(%{error: "unauthorized"})
    end
  end

  defp update_text(postmortem, action_item, user, args) do
    case Map.take(args, ["title", "description", "priority"]) do
      attrs when attrs == %{} -> {:ok, action_item}
      attrs -> Postmortems.update_action_item(postmortem, action_item, attrs, user)
    end
  end

  defp update_completion(postmortem, action_item, user, args) do
    case Map.fetch(args, "completed") do
      {:ok, completed} ->
        Postmortems.set_action_item_completed(postmortem, action_item, completed, user)

      :error ->
        {:ok, action_item}
    end
  end
end

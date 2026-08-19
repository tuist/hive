defmodule Hive.MCP.Components.Tools.CreatePostmortemActionItem do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "create_postmortem_action_item",
    title: "Create Postmortem Action Item",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["postmortem_id", "title"],
      "properties" => %{
        "postmortem_id" => %{
          "type" => "string",
          "description" => "Postmortem identifier, public number, or shared postmortem address."
        },
        "title" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "resolution_url" => %{
          "type" => ["string", "null"],
          "description" => "HTTP or HTTPS link to the work that resolved this action item."
        },
        "priority" => %{
          "type" => "string",
          "enum" => Enum.map(Hive.Postmortems.ActionItem.priorities(), &Atom.to_string/1),
          "description" => "Urgency of the follow-up work. Defaults to medium."
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
  def description, do: "Create an action item for a Hive postmortem. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"postmortem_id" => postmortem_id} = args) do
    user = conn.assigns[:current_user]

    case Postmortems.fetch_visible_postmortem_by_reference(postmortem_id, user) do
      {:ok, postmortem} -> create(postmortem, user, args)
      {:error, :not_found} -> json_response(%{error: "not_found"})
    end
  end

  defp create(postmortem, user, args) do
    attrs = Map.take(args, ["title", "description", "resolution_url", "priority"])

    case Postmortems.create_action_item(postmortem, attrs, user) do
      {:ok, action_item} ->
        json_response(%{action_item: PostmortemTool.action_item_json(action_item)})

      {:error, :unauthorized} ->
        json_response(%{error: "unauthorized"})

      {:error, changeset} ->
        json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
    end
  end
end

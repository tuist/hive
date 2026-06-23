defmodule Hive.MCP.Components.Tools.DeleteSpecComment do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "delete_spec_comment",
    title: "Delete Spec Comment",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "required" => ["comment_id"],
      "properties" => %{
        "comment_id" => %{
          "type" => "string",
          "description" => "Comment UUID returned by get_spec or list_specs."
        }
      }
    }

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description, do: "Delete one of the caller's Hive spec comments."

  @impl EMCP.Tool
  def call(conn, %{"comment_id" => comment_id}) do
    comment = Specs.get_comment!(comment_id)
    spec = Specs.get_spec!(comment.spec_id)

    if Specs.can_view?(spec, conn.assigns.current_user) do
      case Specs.delete_comment(comment, conn.assigns.current_user) do
        {:ok, _comment} ->
          Tool.json_response(%{spec: SpecTool.spec_json(Specs.get_spec!(spec.id))})

        {:error, :unauthorized} ->
          Tool.json_response(%{error: "unauthorized"})
      end
    else
      Tool.json_response(%{error: "not_found"})
    end
  end
end

defmodule Hive.MCP.Components.Tools.UpdateSpecComment do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "update_spec_comment",
    title: "Update Spec Comment",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["comment_id", "body"],
      "properties" => %{
        "comment_id" => %{
          "type" => "string",
          "description" => "Comment UUID returned by get_spec or list_specs."
        },
        "body" => %{"type" => "string"}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"spec" => Hive.MCP.Components.Schemas.spec()},
        ["spec"]
      )

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description, do: "Update one of the caller's Hive spec comments."

  @impl EMCP.Tool
  def call(conn, %{"comment_id" => comment_id} = args) do
    comment = Specs.get_comment!(comment_id)
    spec = Specs.get_spec!(comment.spec_id)

    if Specs.can_view?(spec, conn.assigns.current_user) do
      case Specs.update_comment(comment, Map.take(args, ["body"]), conn.assigns.current_user) do
        {:ok, _comment} ->
          json_response(%{spec: SpecTool.spec_json(Specs.get_spec!(spec.id))})

        {:error, :unauthorized} ->
          json_response(%{error: "unauthorized"})

        {:error, changeset} ->
          json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
      end
    else
      json_response(%{error: "not_found"})
    end
  end
end

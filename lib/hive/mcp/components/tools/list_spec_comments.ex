defmodule Hive.MCP.Components.Tools.ListSpecComments do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_spec_comments",
    title: "List Spec Comments",
    schema: %{
      "type" => "object",
      "required" => ["spec_id"],
      "properties" => %{
        "spec_id" => %{
          "type" => "string",
          "description" => "Spec UUID, public number, or /specs/:number URL."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "spec" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "number" => %{"type" => "integer"},
              "title" => %{"type" => "string"}
            },
            "required" => ["id", "number", "title"],
            "additionalProperties" => false
          },
          "comments" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Tools.Specs.comment_schema()
          }
        },
        ["spec", "comments"]
      )

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.Specs

  @impl EMCP.Tool
  def description, do: "List comments for one visible Hive spec."

  @impl EMCP.Tool
  def call(conn, %{"spec_id" => spec_id}) do
    spec = Specs.get_spec_by_reference!(spec_id)

    if Specs.can_view?(spec, conn.assigns.current_user) do
      json_response(%{
        spec: %{
          id: spec.id,
          number: spec.number,
          title: spec.title
        },
        comments: SpecTool.comments_json(spec)
      })
    else
      json_response(%{error: "not_found"})
    end
  end
end

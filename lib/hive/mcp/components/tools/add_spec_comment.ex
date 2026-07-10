defmodule Hive.MCP.Components.Tools.AddSpecComment do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "add_spec_comment",
    title: "Add Spec Comment",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["spec_id", "body"],
      "properties" => %{
        "spec_id" => %{
          "type" => "string",
          "description" => "Spec UUID, public number, or /specs/:number URL."
        },
        "body" => %{"type" => "string"},
        "author_name" => %{"type" => "string"}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"spec" => Hive.MCP.Components.Tools.Specs.spec_schema()},
        ["spec"]
      )

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description, do: "Add a comment to a Hive spec."

  @impl EMCP.Tool
  def call(conn, %{"spec_id" => spec_id} = args) do
    spec = Specs.get_spec_by_reference!(spec_id)

    if Specs.can_view?(spec, conn.assigns.current_user) do
      case Specs.add_comment(
             spec,
             Map.take(args, ["body", "author_name"]),
             conn.assigns.current_user
           ) do
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

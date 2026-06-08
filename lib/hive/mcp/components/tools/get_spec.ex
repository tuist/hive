defmodule Hive.MCP.Components.Tools.GetSpec do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_spec",
    title: "Get Spec",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Spec UUID, public number, or /specs/:number URL."
        }
      }
    }

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description, do: "Fetch one Hive spec with comments and its current revision."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    spec = Specs.get_spec_by_reference!(id)

    if Specs.can_view?(spec, conn.assigns.current_user) do
      Tool.json_response(%{spec: SpecTool.spec_json(spec)})
    else
      Tool.json_response(%{error: "not_found"})
    end
  end
end

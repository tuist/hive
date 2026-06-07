defmodule Hive.MCP.Components.Tools.GetSpec do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_spec",
    title: "Get Spec",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string"}
      }
    }

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description, do: "Fetch one Hive spec with comments and its current revision."

  @impl EMCP.Tool
  def call(_conn, %{"id" => id}) do
    Tool.json_response(%{spec: SpecTool.spec_json(Specs.get_spec!(id))})
  end
end

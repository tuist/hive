defmodule Hive.MCP.Components.Tools.ListSpecs do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_specs",
    title: "List Specs",
    schema: %{
      "type" => "object",
      "properties" => %{
        "status" => %{"type" => "string"}
      }
    }

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description, do: "List Hive specs, optionally filtered by status."

  @impl EMCP.Tool
  def call(_conn, args) do
    status = args["status"]

    specs =
      Specs.list_specs()
      |> Enum.filter(fn spec -> is_nil(status) or Atom.to_string(spec.status) == status end)

    Tool.json_response(%{specs: Enum.map(specs, &SpecTool.spec_json/1)})
  end
end

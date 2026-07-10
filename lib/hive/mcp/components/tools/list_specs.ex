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
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "specs" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Tools.Specs.spec_schema()
          }
        },
        ["specs"]
      )

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.Specs

  @impl EMCP.Tool
  def description, do: "List Hive specs, optionally filtered by status."

  @impl EMCP.Tool
  def call(conn, args) do
    status = args["status"]

    specs =
      Specs.list_specs(user: conn.assigns.current_user)
      |> Enum.filter(fn spec -> is_nil(status) or Atom.to_string(spec.status) == status end)

    json_response(%{specs: Enum.map(specs, &SpecTool.spec_json/1)})
  end
end

defmodule Hive.MCP.Components.Tools.GetCodingRun do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_coding_run",
    title: "Get Coding Run",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "Coding run identifier."}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"coding_run" => Hive.MCP.Components.Schemas.coding_run()},
        ["coding_run"]
      )

  alias Hive.Forage.CodingRuns
  alias Hive.MCP.Components.Tools.CodingRuns, as: CodingRunTool

  @impl EMCP.Tool
  def description do
    "Fetch the current status and result of one coding run. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    case CodingRuns.get_for_user(id, conn.assigns[:current_user]) do
      nil -> json_response(%{error: "not_found"})
      run -> json_response(%{coding_run: CodingRunTool.coding_run_json(run)})
    end
  end
end

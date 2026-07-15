defmodule Hive.MCP.Components.Tools.GetProject do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_project",
    title: "Get Project",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "Project UUID."}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"project" => Hive.MCP.Components.Schemas.project()},
        ["project"]
      )

  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.Projects

  @impl EMCP.Tool
  def description, do: "Fetch one project with its domains, repositories, and webhooks."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    case Projects.fetch_visible_project(id, conn.assigns[:current_user]) do
      {:ok, project} -> json_response(%{project: ProjectTool.project_json(project)})
      {:error, :not_found} -> json_response(%{error: "not_found"})
    end
  end
end

defmodule Hive.MCP.Components.Tools.ListProjects do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_projects",
    title: "List Projects",
    schema: %{
      "type" => "object",
      "properties" => %{
        "visibility" => %{
          "type" => "string",
          "enum" => ["public", "private"],
          "description" => "Restrict to projects with this visibility."
        }
      }
    }

  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.MCP.Tool
  alias Hive.Projects

  @impl EMCP.Tool
  def description, do: "List projects visible to the authenticated caller."

  @impl EMCP.Tool
  def call(conn, args) do
    visibility = args["visibility"]

    projects =
      conn.assigns[:current_user]
      |> Projects.list_visible_projects()
      |> Enum.filter(fn project ->
        is_nil(visibility) or Atom.to_string(project.visibility) == visibility
      end)

    Tool.json_response(%{projects: Enum.map(projects, &ProjectTool.project_json/1)})
  end
end

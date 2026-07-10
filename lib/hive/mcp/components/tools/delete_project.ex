defmodule Hive.MCP.Components.Tools.DeleteProject do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "delete_project",
    title: "Delete Project",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "Project UUID."}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"deleted_project" => Hive.MCP.Components.Tools.Projects.project_schema()},
        ["deleted_project"]
      )

  alias Hive.Auth
  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.MCP.Tool
  alias Hive.Projects

  @impl EMCP.Tool
  def description, do: "Delete a project. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]

    if Auth.member?(user) do
      delete_project(user, id)
    else
      json_response(%{error: "unauthorized"})
    end
  end

  defp delete_project(user, id) do
    case Projects.fetch_visible_project(id, user) do
      {:ok, project} ->
        deleted_project = ProjectTool.project_json(project)

        case Projects.delete_project(project) do
          {:ok, _project} ->
            json_response(%{deleted_project: deleted_project})

          {:error, changeset} ->
            json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
        end

      {:error, :not_found} ->
        json_response(%{error: "not_found"})
    end
  end
end

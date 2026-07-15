defmodule Hive.MCP.Components.Tools.UnlinkProjectRepository do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "unlink_project_repository",
    title: "Unlink Project Repository",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "required" => ["project_id", "repository_id"],
      "properties" => %{
        "project_id" => %{"type" => "string", "description" => "Project UUID."},
        "repository_id" => %{"type" => "string", "description" => "Repository UUID."}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "project" => Hive.MCP.Components.Schemas.project(),
          "unlinked_repository" => Hive.MCP.Components.Schemas.repository()
        },
        ["project", "unlinked_repository"]
      )

  alias Hive.Auth
  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.Projects

  @impl EMCP.Tool
  def description, do: "Remove a repository link from a project. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"project_id" => project_id, "repository_id" => repository_id}) do
    user = conn.assigns[:current_user]

    with true <- Auth.member?(user),
         {:ok, project} <- Projects.fetch_visible_project(project_id, user) do
      case Projects.delete_repository_from_project(project, repository_id) do
        {:ok, repository} ->
          json_response(%{
            project: project.id |> Projects.get_project!() |> ProjectTool.project_json(),
            unlinked_repository: ProjectTool.repository_json(repository)
          })

        {:error, :not_found} ->
          json_response(%{error: "not_found"})
      end
    else
      false -> json_response(%{error: "unauthorized"})
      {:error, :not_found} -> json_response(%{error: "not_found"})
    end
  end
end

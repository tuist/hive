defmodule Hive.MCP.Components.Tools.LinkProjectRepository do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "link_project_repository",
    title: "Link Project Repository",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["project_id", "owner", "name"],
      "properties" => %{
        "project_id" => %{"type" => "string", "description" => "Project UUID."},
        "owner" => %{"type" => "string", "description" => "GitHub repository owner."},
        "name" => %{"type" => "string", "description" => "GitHub repository name."},
        "visibility" => %{
          "type" => "string",
          "enum" => ["public", "private"],
          "description" => "Repository visibility inside Hive."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "project" => Hive.MCP.Components.Schemas.project(),
          "repository" => Hive.MCP.Components.Schemas.repository()
        },
        ["project", "repository"]
      )

  alias Hive.Auth
  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.MCP.Tool
  alias Hive.Projects

  @impl EMCP.Tool
  def description, do: "Link a GitHub repository to a project. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"project_id" => project_id} = args) do
    user = conn.assigns[:current_user]

    with true <- Auth.member?(user),
         {:ok, project} <- Projects.fetch_visible_project(project_id, user) do
      attrs = Map.take(args, ["owner", "name", "visibility"])

      case Projects.create_repository_for_project(project, attrs) do
        {:ok, repository} ->
          json_response(%{
            project: project.id |> Projects.get_project!() |> ProjectTool.project_json(),
            repository: ProjectTool.repository_json(repository)
          })

        {:error, changeset} ->
          json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
      end
    else
      false -> json_response(%{error: "unauthorized"})
      {:error, :not_found} -> json_response(%{error: "not_found"})
    end
  end
end

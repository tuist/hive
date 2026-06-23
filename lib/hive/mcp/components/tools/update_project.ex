defmodule Hive.MCP.Components.Tools.UpdateProject do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "update_project",
    title: "Update Project",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "Project UUID."},
        "name" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "visibility" => %{
          "type" => "string",
          "enum" => ["public", "private"],
          "description" => "Project visibility."
        }
      }
    }

  alias Hive.Auth
  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.MCP.Tool
  alias Hive.Projects

  @impl EMCP.Tool
  def description, do: "Update a project. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"id" => id} = args) do
    user = conn.assigns[:current_user]

    if Auth.member?(user) do
      update_project(user, id, args)
    else
      Tool.json_response(%{error: "unauthorized"})
    end
  end

  defp update_project(user, id, args) do
    case Projects.fetch_visible_project(id, user) do
      {:ok, project} ->
        attrs = Map.take(args, ["name", "description", "visibility"])

        case Projects.update_project(project, attrs) do
          {:ok, project} ->
            Tool.json_response(%{
              project: project.id |> Projects.get_project!() |> ProjectTool.project_json()
            })

          {:error, changeset} ->
            Tool.json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
        end

      {:error, :not_found} ->
        Tool.json_response(%{error: "not_found"})
    end
  end
end

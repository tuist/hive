defmodule Hive.MCP.Components.Tools.CreateProject do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "create_project",
    title: "Create Project",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{
        "name" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "visibility" => %{
          "type" => "string",
          "enum" => ["public", "private"],
          "description" => "Project visibility."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"project" => Hive.MCP.Components.Schemas.project()},
        ["project"]
      )

  alias Hive.Auth
  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.MCP.Tool
  alias Hive.Projects

  @impl EMCP.Tool
  def description, do: "Create a project. Organization member only."

  @impl EMCP.Tool
  def call(conn, args) do
    if Auth.member?(conn.assigns[:current_user]) do
      args
      |> Map.take(["name", "description", "visibility"])
      |> Projects.create_project()
      |> case do
        {:ok, project} ->
          json_response(%{
            project: project.id |> Projects.get_project!() |> ProjectTool.project_json()
          })

        {:error, changeset} ->
          json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
      end
    else
      json_response(%{error: "unauthorized"})
    end
  end
end

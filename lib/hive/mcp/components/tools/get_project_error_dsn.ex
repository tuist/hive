defmodule Hive.MCP.Components.Tools.GetProjectErrorDsn do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_project_error_dsn",
    title: "Get Project Error DSN",
    schema: %{
      "type" => "object",
      "required" => ["project_id"],
      "properties" => %{
        "project_id" => %{"type" => "string", "description" => "Project identifier."}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"key" => Hive.MCP.Components.Schemas.error_project_key()},
        ["key"]
      )

  alias Hive.Errors
  alias Hive.Errors.Policy
  alias Hive.Projects
  alias HiveWeb.Endpoint

  @impl EMCP.Tool
  def description,
    do:
      "Return the current Sentry-compatible Data Source Name for a project. Lazily provisions one if the project has none. Restricted to organization members."

  @impl EMCP.Tool
  def call(conn, %{"project_id" => project_id}) do
    user = conn.assigns[:current_user]

    if Policy.authorize?(:error_project_key_read, user, nil) do
      fetch_dsn(project_id, user)
    else
      json_response(%{error: "forbidden"})
    end
  end

  defp fetch_dsn(project_id, user) do
    case Projects.fetch_visible_project(project_id, user) do
      {:ok, project} -> serialize_key(project)
      {:error, :not_found} -> json_response(%{error: "not_found"})
    end
  end

  defp serialize_key(project) do
    case Errors.primary_project_key(project) do
      nil -> json_response(%{error: "unavailable"})
      key -> json_response(%{key: Errors.serialize_project_key(key, Endpoint.url())})
    end
  end
end

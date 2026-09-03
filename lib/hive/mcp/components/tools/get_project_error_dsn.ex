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

    cond do
      not Policy.authorize?(:error_project_key_read, user, nil) ->
        json_response(%{error: "forbidden"})

      true ->
        case Projects.fetch_visible_project(project_id, user) do
          {:ok, project} ->
            case Errors.primary_project_key(project) do
              nil -> json_response(%{error: "unavailable"})
              key -> json_response(%{key: Errors.serialize_project_key(key, Endpoint.url())})
            end

          {:error, :not_found} ->
            json_response(%{error: "not_found"})
        end
    end
  end
end

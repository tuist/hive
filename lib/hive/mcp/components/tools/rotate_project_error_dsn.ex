defmodule Hive.MCP.Components.Tools.RotateProjectErrorDsn do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "rotate_project_error_dsn",
    title: "Rotate Project Error DSN",
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
      "Invalidate the current Sentry-compatible Data Source Name for a project and return the freshly minted replacement. Restricted to administrators."

  @impl EMCP.Tool
  def call(conn, %{"project_id" => project_id}) do
    user = conn.assigns[:current_user]

    cond do
      not Policy.authorize?(:error_project_key_create, user, nil) ->
        json_response(%{error: "forbidden"})

      true ->
        case Projects.fetch_visible_project(project_id, user) do
          {:ok, project} ->
            case Errors.rotate_project_key(project) do
              {:ok, key} ->
                json_response(%{key: Errors.serialize_project_key(key, Endpoint.url())})

              {:error, _} ->
                json_response(%{error: "rotation_failed"})
            end

          {:error, :not_found} ->
            json_response(%{error: "not_found"})
        end
    end
  end
end

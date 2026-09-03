defmodule Hive.MCP.Components.Tools.CreateProjectErrorKey do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "create_project_error_key",
    title: "Create Project Error Key",
    schema: %{
      "type" => "object",
      "required" => ["project_id"],
      "properties" => %{
        "project_id" => %{"type" => "string", "description" => "Project to mint the key for."},
        "name" => %{
          "type" => "string",
          "description" => "Label for the key, e.g. \"production\". Defaults to \"default\"."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"key" => Hive.MCP.Components.Schemas.error_project_key()},
        ["key"]
      )

  alias Hive.Errors
  alias Hive.Errors.Policy
  alias HiveWeb.Endpoint

  @impl EMCP.Tool
  def description,
    do:
      "Mint a Sentry-compatible Data Source Name for a project so a Software Development Kit can send events to it. Restricted to admins."

  @impl EMCP.Tool
  def call(conn, %{"project_id" => project_id} = args) do
    user = conn.assigns[:current_user]
    name = Map.get(args, "name", "default")

    cond do
      not Policy.authorize?(:error_project_key_create, user, nil) ->
        json_response(%{error: "forbidden"})

      true ->
        case Errors.create_project_key(project_id, %{"name" => name}) do
          {:ok, key} ->
            json_response(%{key: Errors.serialize_project_key(key, Endpoint.url())})

          {:error, changeset} ->
            json_response(%{error: "invalid", detail: inspect(changeset.errors)})
        end
    end
  end
end

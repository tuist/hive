defmodule Hive.MCP.Components.Tools.DeleteSpec do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "delete_spec",
    title: "Delete Spec",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "required" => ["id", "expected_revision"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Spec identifier, public number, or shared spec address."
        },
        "expected_revision" => %{
          "type" => "integer",
          "description" => "Revision returned by get_spec or list_specs."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"deleted_spec" => Hive.MCP.Components.Schemas.spec()},
        ["deleted_spec"],
        %{
          "current_revision" => %{"type" => "integer"},
          "spec" => Hive.MCP.Components.Schemas.spec()
        }
      )

  alias Hive.Auth
  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description do
    "Delete a Hive spec after checking the expected revision. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, %{"id" => id, "expected_revision" => expected_revision}) do
    user = conn.assigns[:current_user]

    if Auth.member?(user) do
      delete(user, id, expected_revision)
    else
      json_response(%{error: "unauthorized"})
    end
  end

  defp delete(user, id, expected_revision) do
    case Specs.fetch_visible_spec_by_reference(id, user) do
      {:ok, %{lock_version: ^expected_revision} = spec} ->
        deleted_spec = SpecTool.spec_json(spec)

        case Specs.delete_spec(spec, user) do
          {:ok, _spec} ->
            json_response(%{deleted_spec: deleted_spec})

          {:error, :unauthorized} ->
            json_response(%{error: "unauthorized"})

          {:error, :stale} ->
            stale_response(user, id)

          {:error, changeset} ->
            json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
        end

      {:ok, spec} ->
        json_response(%{
          error: "stale_revision",
          current_revision: spec.lock_version,
          spec: SpecTool.spec_json(spec)
        })

      {:error, :not_found} ->
        json_response(%{error: "not_found"})
    end
  end

  defp stale_response(user, id) do
    case Specs.fetch_visible_spec_by_reference(id, user) do
      {:ok, spec} ->
        json_response(%{
          error: "stale_revision",
          current_revision: spec.lock_version,
          spec: SpecTool.spec_json(spec)
        })

      {:error, :not_found} ->
        json_response(%{error: "not_found"})
    end
  end
end

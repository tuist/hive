defmodule Hive.MCP.Components.Tools.RotateDomainErrorDsn do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "rotate_domain_error_dsn",
    title: "Rotate Domain Error DSN",
    schema: %{
      "type" => "object",
      "required" => ["project_id", "domain_id"],
      "properties" => %{
        "project_id" => %{"type" => "string", "description" => "Project identifier."},
        "domain_id" => %{
          "type" => "string",
          "description" => "Domain identifier. Must be linked to the project."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"key" => Hive.MCP.Components.Schemas.error_project_key()},
        ["key"]
      )

  alias Hive.Domains
  alias Hive.Errors
  alias Hive.Errors.Policy
  alias Hive.Projects
  alias HiveWeb.Endpoint

  @impl EMCP.Tool
  def description,
    do:
      "Invalidate the current Sentry-compatible Data Source Name for a (project, domain) pair and return the freshly minted replacement. Only that one credential is affected; the project-level DSN and every other domain's DSN keep working. Restricted to administrators."

  @impl EMCP.Tool
  def call(conn, %{"project_id" => project_id, "domain_id" => domain_id}) do
    user = conn.assigns[:current_user]

    if Policy.authorize?(:error_project_key_create, user, nil) do
      rotate(project_id, domain_id, user)
    else
      json_response(%{error: "forbidden"})
    end
  end

  defp rotate(project_id, domain_id, user) do
    with {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         {:ok, domain} <- Domains.fetch_visible_domain(domain_id, user),
         :ok <- ensure_linked(project, domain) do
      rotate_key(project, domain)
    else
      {:error, :not_found} -> json_response(%{error: "not_found"})
      {:error, :not_linked} -> json_response(%{error: "domain_not_linked_to_project"})
    end
  end

  defp ensure_linked(project, domain) do
    if Enum.any?(domain.projects, &(&1.id == project.id)),
      do: :ok,
      else: {:error, :not_linked}
  end

  defp rotate_key(project, domain) do
    case Errors.rotate_domain_key(project, domain) do
      {:ok, key} -> json_response(%{key: Errors.serialize_project_key(key, Endpoint.url())})
      {:error, _} -> json_response(%{error: "rotation_failed"})
    end
  end
end

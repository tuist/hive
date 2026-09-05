defmodule Hive.MCP.Components.Tools.GetDomainErrorDsn do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_domain_error_dsn",
    title: "Get Domain Error DSN",
    schema: %{
      "type" => "object",
      "required" => ["project_id", "domain_id"],
      "properties" => %{
        "project_id" => %{"type" => "string", "description" => "Project identifier."},
        "domain_id" => %{
          "type" => "string",
          "description" =>
            "Domain identifier. The domain must already be linked to the project; link it first with link_project_domain."
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
      "Return the current Sentry-compatible Data Source Name that attributes events to a specific (project, domain) pair at ingest time. Any Sentry SDK pointed at this URL lands events tagged with the domain without any per-caller SDK change. Lazily provisions the credential on first read. Restricted to organization members; the domain must be linked to the project first with link_project_domain."

  @impl EMCP.Tool
  def call(conn, %{"project_id" => project_id, "domain_id" => domain_id}) do
    user = conn.assigns[:current_user]

    if Policy.authorize?(:error_project_key_read, user, nil) do
      fetch_dsn(project_id, domain_id, user)
    else
      json_response(%{error: "forbidden"})
    end
  end

  defp fetch_dsn(project_id, domain_id, user) do
    with {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         {:ok, domain} <- Domains.fetch_visible_domain(domain_id, user),
         :ok <- ensure_linked(project, domain) do
      serialize_key(project, domain)
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

  defp serialize_key(project, domain) do
    case Errors.primary_domain_key(project, domain) do
      nil -> json_response(%{error: "unavailable"})
      key -> json_response(%{key: Errors.serialize_project_key(key, Endpoint.url())})
    end
  end
end

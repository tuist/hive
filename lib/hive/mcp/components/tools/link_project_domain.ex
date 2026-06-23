defmodule Hive.MCP.Components.Tools.LinkProjectDomain do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "link_project_domain",
    title: "Link Project Domain",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["project_id", "domain_id"],
      "properties" => %{
        "project_id" => %{"type" => "string", "description" => "Project UUID."},
        "domain_id" => %{"type" => "string", "description" => "Domain UUID."}
      }
    }

  alias Hive.Auth
  alias Hive.Domains
  alias Hive.MCP.Components.Tools.Domains, as: DomainTool
  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.MCP.Tool
  alias Hive.Projects

  @impl EMCP.Tool
  def description, do: "Link an existing domain to a project. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"project_id" => project_id, "domain_id" => domain_id}) do
    user = conn.assigns[:current_user]

    with true <- Auth.member?(user),
         {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         {:ok, domain} <- Domains.fetch_visible_domain(domain_id, user),
         {:ok, _domain} <- Projects.link_domain_to_project(project, domain.id) do
      Tool.json_response(%{
        project: project.id |> Projects.get_project!() |> ProjectTool.project_json(),
        domain: domain.id |> Domains.get_domain!() |> DomainTool.domain_json()
      })
    else
      false -> Tool.json_response(%{error: "unauthorized"})
      {:error, :not_found} -> Tool.json_response(%{error: "not_found"})
    end
  end
end

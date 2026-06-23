defmodule Hive.MCP.Components.Tools.UnlinkProjectDomainTest do
  use Hive.MCPToolCase

  alias Hive.Domains
  alias Hive.MCP.Components.Tools.UnlinkProjectDomain
  alias Hive.Projects

  test "unlinks a domain from a project" do
    user = mcp_user("unlink-project-domain@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})
    {:ok, domain} = Domains.create_domain(%{name: unique_name("Cache")})
    {:ok, _domain} = Projects.link_domain_to_project(project, domain.id)

    response =
      user
      |> mcp_conn()
      |> UnlinkProjectDomain.call(%{"project_id" => project.id, "domain_id" => domain.id})
      |> response_json()

    assert response["unlinked_domain"]["id"] == domain.id
    assert response["project"]["domains"] == []
    assert Projects.get_project!(project.id).domains == []
  end

  test "rejects collaborators" do
    user = mcp_user("unlink-project-domain-collaborator@example.com", :collaborator)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})
    {:ok, domain} = Domains.create_domain(%{name: unique_name("Cache")})
    {:ok, _domain} = Projects.link_domain_to_project(project, domain.id)

    response =
      user
      |> mcp_conn()
      |> UnlinkProjectDomain.call(%{"project_id" => project.id, "domain_id" => domain.id})
      |> response_json()

    assert response == %{"error" => "unauthorized"}
    assert Projects.get_project!(project.id).domains |> Enum.map(& &1.id) == [domain.id]
  end
end

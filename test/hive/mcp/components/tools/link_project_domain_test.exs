defmodule Hive.MCP.Components.Tools.LinkProjectDomainTest do
  use Hive.MCPToolCase

  alias Hive.Domains
  alias Hive.MCP.Components.Tools.LinkProjectDomain
  alias Hive.Projects

  test "links an existing domain to a project" do
    user = mcp_user("link-project-domain@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})
    {:ok, domain} = Domains.create_domain(%{name: unique_name("Cache")})

    response =
      user
      |> mcp_conn()
      |> LinkProjectDomain.call(%{"project_id" => project.id, "domain_id" => domain.id})
      |> response_json()

    assert response["project"]["domains"] |> Enum.map(& &1["id"]) == [domain.id]
    assert response["domain"]["projects"] |> Enum.map(& &1["id"]) == [project.id]
  end

  test "rejects collaborators" do
    user = mcp_user("link-project-domain-collaborator@example.com", :collaborator)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})
    {:ok, domain} = Domains.create_domain(%{name: unique_name("Cache")})

    response =
      user
      |> mcp_conn()
      |> LinkProjectDomain.call(%{"project_id" => project.id, "domain_id" => domain.id})
      |> response_json()

    assert response == %{"error" => "unauthorized"}
    assert Projects.get_project!(project.id).domains == []
  end
end

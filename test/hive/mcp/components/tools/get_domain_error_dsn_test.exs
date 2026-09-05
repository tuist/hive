defmodule Hive.MCP.Components.Tools.GetDomainErrorDsnTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Domains
  alias Hive.MCP.Components.Tools.GetDomainErrorDsn
  alias Hive.Projects

  setup :verify_on_exit!

  setup do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    stub(Hive.IngestRepo, :insert_all, fn _table, rows, _opts -> {length(rows), nil} end)

    {:ok, project} = Projects.create_project(%{"name" => unique_name("Proj")})
    {:ok, domain} = Domains.create_domain(%{"name" => unique_name("Dom"), "visibility" => "public"})
    :ok = Domains.link_domain_to_project(domain, project.id)

    {:ok, project: project, domain: domain}
  end

  test "returns the (project, domain) DSN for members", %{project: project, domain: domain} do
    user = mcp_user("member@example.com", :member)

    response =
      GetDomainErrorDsn.call(mcp_conn(user), %{
        "project_id" => project.id,
        "domain_id" => domain.id
      })

    assert %{"key" => %{"dsn" => "http" <> _, "domain_id" => returned_domain_id}} =
             response_json(response)

    assert returned_domain_id == domain.id
  end

  test "rejects non-members", %{project: project, domain: domain} do
    outsider = mcp_user("guest@example.com", :collaborator)

    response =
      GetDomainErrorDsn.call(mcp_conn(outsider), %{
        "project_id" => project.id,
        "domain_id" => domain.id
      })

    assert response_json(response) == %{"error" => "forbidden"}
  end

  test "returns not_found for an unknown project", %{domain: domain} do
    user = mcp_user("member@example.com", :member)

    response =
      GetDomainErrorDsn.call(mcp_conn(user), %{
        "project_id" => "00000000-0000-0000-0000-000000000000",
        "domain_id" => domain.id
      })

    assert response_json(response) == %{"error" => "not_found"}
  end

  test "refuses when the domain is not linked to the project", %{project: project} do
    user = mcp_user("member@example.com", :member)

    {:ok, other_domain} =
      Domains.create_domain(%{"name" => unique_name("Other"), "visibility" => "public"})

    response =
      GetDomainErrorDsn.call(mcp_conn(user), %{
        "project_id" => project.id,
        "domain_id" => other_domain.id
      })

    assert response_json(response) == %{"error" => "domain_not_linked_to_project"}
  end
end

defmodule Hive.MCP.Components.Tools.RotateDomainErrorDsnTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Domains
  alias Hive.Errors
  alias Hive.MCP.Components.Tools.RotateDomainErrorDsn
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

  test "admin rotates the domain-scoped key and receives a new DSN",
       %{project: project, domain: domain} do
    admin = mcp_user("admin@example.com", :admin)
    {:ok, before_key} = Errors.create_domain_key(project.id, domain.id)

    response =
      RotateDomainErrorDsn.call(mcp_conn(admin), %{
        "project_id" => project.id,
        "domain_id" => domain.id
      })

    assert %{"key" => %{"dsn" => "http" <> _, "public_key" => public_key, "domain_id" => did}} =
             response_json(response)

    refute public_key == before_key.public_key
    assert did == domain.id
  end

  test "rotating the domain key does not touch the project-level key",
       %{project: project, domain: domain} do
    admin = mcp_user("admin@example.com", :admin)
    {:ok, project_key} = Errors.create_project_key(project.id)
    {:ok, _domain_key} = Errors.create_domain_key(project.id, domain.id)

    _ =
      RotateDomainErrorDsn.call(mcp_conn(admin), %{
        "project_id" => project.id,
        "domain_id" => domain.id
      })

    assert {:ok, refetched} = Errors.fetch_project_key_by_public_key(project_key.public_key)
    assert refetched.id == project_key.id
  end

  test "members without admin cannot rotate", %{project: project, domain: domain} do
    member = mcp_user("member@example.com", :member)

    response =
      RotateDomainErrorDsn.call(mcp_conn(member), %{
        "project_id" => project.id,
        "domain_id" => domain.id
      })

    assert response_json(response) == %{"error" => "forbidden"}
  end
end

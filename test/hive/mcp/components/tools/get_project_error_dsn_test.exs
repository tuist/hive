defmodule Hive.MCP.Components.Tools.GetProjectErrorDsnTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.MCP.Components.Tools.GetProjectErrorDsn
  alias Hive.Projects

  setup :verify_on_exit!

  setup do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    stub(Hive.IngestRepo, :insert_all, fn _table, rows, _opts -> {length(rows), nil} end)

    {:ok, project} = Projects.create_project(%{"name" => unique_name("Proj")})
    {:ok, project: project}
  end

  test "returns the project DSN for members", %{project: project} do
    user = mcp_user("member@example.com", :member)

    response = GetProjectErrorDsn.call(mcp_conn(user), %{"project_id" => project.id})
    assert %{"key" => %{"dsn" => "http" <> _}} = response_json(response)
  end

  test "rejects non-members", %{project: project} do
    outsider = mcp_user("guest@example.com", :collaborator)
    response = GetProjectErrorDsn.call(mcp_conn(outsider), %{"project_id" => project.id})
    assert response_json(response) == %{"error" => "forbidden"}
  end

  test "returns not_found for an unknown project" do
    user = mcp_user("member@example.com", :member)

    response =
      GetProjectErrorDsn.call(mcp_conn(user), %{
        "project_id" => "00000000-0000-0000-0000-000000000000"
      })

    assert response_json(response) == %{"error" => "not_found"}
  end
end

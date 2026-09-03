defmodule Hive.MCP.Components.Tools.RotateProjectErrorDsnTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Errors
  alias Hive.MCP.Components.Tools.RotateProjectErrorDsn
  alias Hive.Projects

  setup :verify_on_exit!

  setup do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    stub(Hive.IngestRepo, :insert_all, fn _table, rows, _opts -> {length(rows), nil} end)

    {:ok, project} = Projects.create_project(%{"name" => unique_name("Proj")})
    {:ok, project: project}
  end

  test "admin rotates the key and receives a new DSN", %{project: project} do
    admin = mcp_user("admin@example.com", :admin)
    {:ok, before_key} = Errors.create_project_key(project.id)

    response = RotateProjectErrorDsn.call(mcp_conn(admin), %{"project_id" => project.id})

    assert %{"key" => %{"dsn" => "http" <> _, "public_key" => public_key}} =
             response_json(response)

    refute public_key == before_key.public_key
  end

  test "members without admin cannot rotate", %{project: project} do
    member = mcp_user("member@example.com", :member)
    response = RotateProjectErrorDsn.call(mcp_conn(member), %{"project_id" => project.id})
    assert response_json(response) == %{"error" => "forbidden"}
  end
end

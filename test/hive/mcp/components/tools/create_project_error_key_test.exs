defmodule Hive.MCP.Components.Tools.CreateProjectErrorKeyTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.CreateProjectErrorKey
  alias Hive.Projects

  setup do
    {:ok, project} = Projects.create_project(%{"name" => unique_name("Proj")})
    {:ok, project: project}
  end

  test "admin can mint a key and receives a Data Source Name string", %{project: project} do
    admin = mcp_user("admin@example.com", :admin)

    response =
      CreateProjectErrorKey.call(
        mcp_conn(admin),
        %{"project_id" => project.id, "name" => "production"}
      )

    assert %{
             "key" => %{
               "name" => "production",
               "dsn" => "http" <> _rest,
               "public_key" => public_key
             }
           } = response_json(response)

    assert byte_size(public_key) == 32
  end

  test "members without admin cannot mint", %{project: project} do
    member = mcp_user("member@example.com", :member)

    response = CreateProjectErrorKey.call(mcp_conn(member), %{"project_id" => project.id})
    assert response_json(response) == %{"error" => "forbidden"}
  end
end

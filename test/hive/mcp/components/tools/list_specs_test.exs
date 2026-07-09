defmodule Hive.MCP.Components.Tools.ListSpecsTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.ListSpecs
  alias Hive.Projects
  alias Hive.Specs

  test "lists visible specs" do
    user = mcp_user()
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, spec} =
      Specs.create_spec(
        %{"title" => "Draft", "body" => "Initial proposal.", "project_id" => project.id},
        user
      )

    response = ListSpecs.call(mcp_conn(user), %{}) |> response_json()

    assert [%{"id" => id, "project" => %{"id" => project_id}}] = response["specs"]
    assert id == spec.id
    assert project_id == project.id
  end
end

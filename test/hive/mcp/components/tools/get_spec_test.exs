defmodule Hive.MCP.Components.Tools.GetSpecTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.GetSpec
  alias Hive.Projects
  alias Hive.Specs

  test "fetches specs referenced by shared URL" do
    user = mcp_user()
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, spec} =
      Specs.create_spec(
        %{"title" => "Draft", "body" => "Initial proposal.", "project_id" => project.id},
        user
      )

    response =
      GetSpec.call(mcp_conn(user), %{"id" => "https://hive.test/specs/#{spec.number}"})
      |> response_json()

    assert response["spec"]["id"] == spec.id
    assert response["spec"]["title"] == "Draft"
    assert response["spec"]["project"]["id"] == project.id
  end
end

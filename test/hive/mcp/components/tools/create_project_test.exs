defmodule Hive.MCP.Components.Tools.CreateProjectTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.CreateProject
  alias Hive.Projects

  test "creates a project for members" do
    user = mcp_user("create-project@example.com", :member)
    name = unique_name("Atlas")

    response =
      user
      |> mcp_conn()
      |> CreateProject.call(%{
        "name" => name,
        "description" => "Agentic operations.",
        "visibility" => "private"
      })
      |> response_json()

    assert %{"project" => %{"id" => id, "name" => ^name, "visibility" => "private"}} = response
    assert Projects.get_project!(id).description == "Agentic operations."
  end

  test "rejects collaborators" do
    user = mcp_user("create-project-collaborator@example.com", :collaborator)

    response =
      user
      |> mcp_conn()
      |> CreateProject.call(%{"name" => unique_name("Atlas")})
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end
end

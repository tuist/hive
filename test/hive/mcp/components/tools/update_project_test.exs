defmodule Hive.MCP.Components.Tools.UpdateProjectTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.UpdateProject
  alias Hive.Projects

  test "updates a project for members" do
    user = mcp_user("update-project@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})
    new_name = unique_name("Hive Updated")

    response =
      user
      |> mcp_conn()
      |> UpdateProject.call(%{
        "id" => project.id,
        "name" => new_name,
        "description" => "Updated description.",
        "visibility" => "private"
      })
      |> response_json()

    assert response["project"]["name"] == new_name
    assert response["project"]["visibility"] == "private"
    assert Projects.get_project!(project.id).description == "Updated description."
  end

  test "rejects collaborators" do
    user = mcp_user("update-project-collaborator@example.com", :collaborator)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    response =
      user
      |> mcp_conn()
      |> UpdateProject.call(%{"id" => project.id, "name" => unique_name("Denied")})
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end
end

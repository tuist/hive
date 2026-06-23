defmodule Hive.MCP.Components.Tools.DeleteProjectTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.DeleteProject
  alias Hive.Projects
  alias Hive.Repo

  test "deletes a project for members" do
    user = mcp_user("delete-project@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    response =
      user
      |> mcp_conn()
      |> DeleteProject.call(%{"id" => project.id})
      |> response_json()

    assert response["deleted_project"]["id"] == project.id
    refute Repo.get(Hive.Projects.Project, project.id)
  end

  test "rejects collaborators" do
    user = mcp_user("delete-project-collaborator@example.com", :collaborator)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    response =
      user
      |> mcp_conn()
      |> DeleteProject.call(%{"id" => project.id})
      |> response_json()

    assert response == %{"error" => "unauthorized"}
    assert Projects.get_project!(project.id)
  end
end

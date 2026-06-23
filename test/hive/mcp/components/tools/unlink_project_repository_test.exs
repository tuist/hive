defmodule Hive.MCP.Components.Tools.UnlinkProjectRepositoryTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.UnlinkProjectRepository
  alias Hive.Projects

  test "unlinks a repository from a project" do
    user = mcp_user("unlink-project-repository@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{
        "owner" => "tuist",
        "name" => "hive-#{System.unique_integer([:positive])}"
      })

    response =
      user
      |> mcp_conn()
      |> UnlinkProjectRepository.call(%{
        "project_id" => project.id,
        "repository_id" => repository.id
      })
      |> response_json()

    assert response["unlinked_repository"]["id"] == repository.id
    assert response["project"]["repositories"] == []
  end

  test "returns not found for a repository outside the project" do
    user = mcp_user("unlink-project-repository-not-found@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})
    {:ok, other_project} = Projects.create_project(%{name: unique_name("Atlas")})

    {:ok, repository} =
      Projects.create_repository_for_project(other_project, %{
        "owner" => "tuist",
        "name" => "atlas-#{System.unique_integer([:positive])}"
      })

    response =
      user
      |> mcp_conn()
      |> UnlinkProjectRepository.call(%{
        "project_id" => project.id,
        "repository_id" => repository.id
      })
      |> response_json()

    assert response == %{"error" => "not_found"}
  end
end

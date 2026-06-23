defmodule Hive.MCP.Components.Tools.LinkProjectRepositoryTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.LinkProjectRepository
  alias Hive.Projects

  test "links a repository to a project" do
    user = mcp_user("link-project-repository@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    response =
      user
      |> mcp_conn()
      |> LinkProjectRepository.call(%{
        "project_id" => project.id,
        "owner" => "tuist",
        "name" => "hive-#{System.unique_integer([:positive])}",
        "visibility" => "private"
      })
      |> response_json()

    assert response["repository"]["owner"] == "tuist"
    assert response["repository"]["visibility"] == "private"
    assert [_repository] = Projects.get_project!(project.id).github_repositories
  end

  test "rejects collaborators" do
    user = mcp_user("link-project-repository-collaborator@example.com", :collaborator)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    response =
      user
      |> mcp_conn()
      |> LinkProjectRepository.call(%{
        "project_id" => project.id,
        "owner" => "tuist",
        "name" => "hive-#{System.unique_integer([:positive])}"
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
    assert Projects.get_project!(project.id).github_repositories == []
  end
end

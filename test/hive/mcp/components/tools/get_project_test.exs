defmodule Hive.MCP.Components.Tools.GetProjectTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.GetProject
  alias Hive.Projects

  test "returns a visible project with linked resources" do
    user = mcp_user("get-project@example.com", :member)

    {:ok, project} =
      Projects.create_project(%{name: unique_name("Hive"), description: "Agentic product work."})

    response =
      user
      |> mcp_conn()
      |> GetProject.call(%{"id" => project.id})
      |> response_json()

    assert response["project"]["id"] == project.id
    assert response["project"]["description"] == "Agentic product work."
    assert response["project"]["domains"] == []
    assert response["project"]["repositories"] == []
    assert response["project"]["webhooks"] == []
  end

  test "hides private projects from collaborators" do
    user = mcp_user("get-project-collaborator@example.com", :collaborator)

    {:ok, project} =
      Projects.create_project(%{name: unique_name("Private"), visibility: "private"})

    response =
      user
      |> mcp_conn()
      |> GetProject.call(%{"id" => project.id})
      |> response_json()

    assert response == %{"error" => "not_found"}
  end
end

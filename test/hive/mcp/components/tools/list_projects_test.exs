defmodule Hive.MCP.Components.Tools.ListProjectsTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.ListProjects
  alias Hive.Projects

  test "lists visible projects for the caller" do
    member = mcp_user("member-projects@example.com", :member)
    collaborator = mcp_user("collaborator-projects@example.com", :collaborator)

    {:ok, public_project} =
      Projects.create_project(%{name: unique_name("Public"), visibility: "public"})

    {:ok, private_project} =
      Projects.create_project(%{name: unique_name("Private"), visibility: "private"})

    collaborator_response =
      collaborator
      |> mcp_conn()
      |> ListProjects.call(%{})
      |> response_json()

    assert Enum.map(collaborator_response["projects"], & &1["id"]) == [public_project.id]

    member_response =
      member
      |> mcp_conn()
      |> ListProjects.call(%{})
      |> response_json()

    assert member_response["projects"] |> Enum.map(& &1["id"]) |> Enum.sort() ==
             [private_project.id, public_project.id] |> Enum.sort()
  end

  test "filters by visibility" do
    user = mcp_user("project-filter@example.com", :member)

    {:ok, public_project} =
      Projects.create_project(%{name: unique_name("Public"), visibility: "public"})

    {:ok, _private_project} =
      Projects.create_project(%{name: unique_name("Private"), visibility: "private"})

    response =
      user
      |> mcp_conn()
      |> ListProjects.call(%{"visibility" => "public"})
      |> response_json()

    assert Enum.map(response["projects"], & &1["id"]) == [public_project.id]
  end
end

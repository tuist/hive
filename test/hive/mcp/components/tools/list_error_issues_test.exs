defmodule Hive.MCP.Components.Tools.ListErrorIssuesTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Errors
  alias Hive.Errors.SentryEvent
  alias Hive.MCP.Components.Tools.ListErrorIssues
  alias Hive.Projects

  setup :verify_on_exit!

  setup do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    :ok
  end

  test "returns issues visible to organization members" do
    user = mcp_user("member@example.com", :member)
    {:ok, project} = Projects.create_project(%{"name" => unique_name("Proj")})

    {:ok, _issue} =
      Hive.ErrorsHelpers.seed_issue(
        project,
        SentryEvent.parse(%{"message" => "database timeout"})
      )

    response = ListErrorIssues.call(mcp_conn(user), %{"project_id" => project.id})
    data = response_json(response)

    assert length(data["issues"]) == 1
    assert hd(data["issues"])["title"] == "database timeout"
    assert data["pagination"]["total_count"] == 1
  end

  test "filters by status" do
    user = mcp_user("member@example.com", :member)
    {:ok, project} = Projects.create_project(%{"name" => unique_name("Proj")})

    {:ok, issue} =
      Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "one"}))

    {:ok, _} =
      Hive.ErrorsHelpers.seed_issue(
        project,
        SentryEvent.parse(%{"exception" => %{"values" => [%{"type" => "two"}]}})
      )

    {:ok, _} = Errors.update_issue_status(issue, :resolved)

    response =
      ListErrorIssues.call(
        mcp_conn(user),
        %{"project_id" => project.id, "status" => "resolved"}
      )

    assert %{"issues" => [%{"title" => "one"}]} = response_json(response)
  end

  test "rejects non-members" do
    outsider = mcp_user("guest@example.com", :collaborator)
    response = ListErrorIssues.call(mcp_conn(outsider), %{})
    assert response_json(response) == %{"error" => "forbidden"}
  end
end

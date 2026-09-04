defmodule Hive.MCP.Components.Tools.UnresolveErrorIssueTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Errors
  alias Hive.Errors.SentryEvent
  alias Hive.MCP.Components.Tools.UnresolveErrorIssue
  alias Hive.Projects

  setup :verify_on_exit!

  setup do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)

    {:ok, project} = Projects.create_project(%{"name" => unique_name("Proj")})

    {:ok, issue} =
      Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "boom"}))

    {:ok, resolved} = Errors.update_issue_status(issue, :resolved)

    {:ok, issue: resolved}
  end

  test "returns the issue to unresolved for a member", %{issue: issue} do
    user = mcp_user("member@example.com", :member)

    response = UnresolveErrorIssue.call(mcp_conn(user), %{"id" => issue.id})
    assert %{"issue" => %{"status" => "unresolved"}} = response_json(response)
  end

  test "returns forbidden for non-members", %{issue: issue} do
    outsider = mcp_user("guest@example.com", :collaborator)
    response = UnresolveErrorIssue.call(mcp_conn(outsider), %{"id" => issue.id})
    assert response_json(response) == %{"error" => "forbidden"}
  end
end

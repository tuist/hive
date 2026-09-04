defmodule Hive.MCP.Components.Tools.GetErrorIssueTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Errors.SentryEvent
  alias Hive.MCP.Components.Tools.GetErrorIssue
  alias Hive.Projects

  setup :verify_on_exit!

  setup do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)

    {:ok, project} = Projects.create_project(%{"name" => unique_name("Proj")})

    {:ok, issue} =
      Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "boom"}))

    {:ok, issue: issue}
  end

  test "returns the issue when the caller is a member", %{issue: issue} do
    user = mcp_user("member@example.com", :member)

    response = GetErrorIssue.call(mcp_conn(user), %{"id" => issue.id})

    assert %{
             "issue" => %{
               "title" => "boom",
               "url" => url
             }
           } = response_json(response)

    assert url == "#{HiveWeb.Endpoint.url()}/errors/#{issue.id}"
  end

  test "returns not_found for missing ids" do
    user = mcp_user("member@example.com", :member)

    response =
      GetErrorIssue.call(mcp_conn(user), %{"id" => "00000000-0000-0000-0000-000000000000"})

    assert response_json(response) == %{"error" => "not_found"}
  end

  test "rejects non-members", %{issue: issue} do
    outsider = mcp_user("guest@example.com", :collaborator)
    response = GetErrorIssue.call(mcp_conn(outsider), %{"id" => issue.id})
    assert response_json(response) == %{"error" => "forbidden"}
  end
end

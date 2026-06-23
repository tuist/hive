defmodule Hive.MCP.Components.Tools.CreateProjectWebhookTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.CreateProjectWebhook
  alias Hive.Projects
  alias Hive.Projects.Webhooks

  test "creates a project webhook and returns the one-time URL" do
    user = mcp_user("create-project-webhook@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    response =
      user
      |> mcp_conn()
      |> CreateProjectWebhook.call(%{
        "project_id" => project.id,
        "name" => "Grafana",
        "source" => "grafana"
      })
      |> response_json()

    assert response["webhook"]["name"] == "Grafana"
    assert response["webhook_url"] =~ "/webhooks/projects/#{project.id}/grafana/hwh_"
    assert [_webhook] = Webhooks.list_for_project(project)
  end

  test "rejects collaborators" do
    user = mcp_user("create-project-webhook-collaborator@example.com", :collaborator)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    response =
      user
      |> mcp_conn()
      |> CreateProjectWebhook.call(%{
        "project_id" => project.id,
        "name" => "Grafana",
        "source" => "grafana"
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
    assert Webhooks.list_for_project(project) == []
  end
end

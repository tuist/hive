defmodule Hive.MCP.Components.Tools.DeleteProjectWebhookTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.DeleteProjectWebhook
  alias Hive.Projects
  alias Hive.Projects.Webhooks

  test "deletes a project webhook" do
    user = mcp_user("delete-project-webhook@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, {webhook, _token}} =
      Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    response =
      user
      |> mcp_conn()
      |> DeleteProjectWebhook.call(%{"project_id" => project.id, "webhook_id" => webhook.id})
      |> response_json()

    assert response["deleted_webhook"]["id"] == webhook.id
    assert Webhooks.list_for_project(project) == []
  end

  test "rejects collaborators" do
    user = mcp_user("delete-project-webhook-collaborator@example.com", :collaborator)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, {webhook, _token}} =
      Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    response =
      user
      |> mcp_conn()
      |> DeleteProjectWebhook.call(%{"project_id" => project.id, "webhook_id" => webhook.id})
      |> response_json()

    assert response == %{"error" => "unauthorized"}
    assert [_webhook] = Webhooks.list_for_project(project)
  end
end

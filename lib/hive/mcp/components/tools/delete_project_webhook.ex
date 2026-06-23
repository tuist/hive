defmodule Hive.MCP.Components.Tools.DeleteProjectWebhook do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "delete_project_webhook",
    title: "Delete Project Webhook",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "required" => ["project_id", "webhook_id"],
      "properties" => %{
        "project_id" => %{"type" => "string", "description" => "Project UUID."},
        "webhook_id" => %{"type" => "string", "description" => "Webhook UUID."}
      }
    }

  alias Hive.Auth
  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.MCP.Tool
  alias Hive.Projects
  alias Hive.Projects.Webhooks

  @impl EMCP.Tool
  def description, do: "Delete a project webhook. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"project_id" => project_id, "webhook_id" => webhook_id}) do
    user = conn.assigns[:current_user]

    with true <- Auth.member?(user),
         {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         webhook when not is_nil(webhook) <- find_webhook(project, webhook_id),
         {:ok, deleted_webhook} <- Webhooks.delete(webhook) do
      Tool.json_response(%{
        project: project.id |> Projects.get_project!() |> ProjectTool.project_json(),
        deleted_webhook: ProjectTool.webhook_json(deleted_webhook)
      })
    else
      false ->
        Tool.json_response(%{error: "unauthorized"})

      nil ->
        Tool.json_response(%{error: "not_found"})

      {:error, :not_found} ->
        Tool.json_response(%{error: "not_found"})

      {:error, changeset} ->
        Tool.json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
    end
  end

  defp find_webhook(project, webhook_id) do
    project
    |> Webhooks.list_for_project()
    |> Enum.find(&(&1.id == webhook_id))
  end
end

defmodule Hive.MCP.Components.Tools.CreateProjectWebhook do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "create_project_webhook",
    title: "Create Project Webhook",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["project_id", "name", "source"],
      "properties" => %{
        "project_id" => %{"type" => "string", "description" => "Project UUID."},
        "name" => %{"type" => "string"},
        "source" => %{
          "type" => "string",
          "enum" => ["grafana"],
          "description" => "External source that will call the webhook."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "project" => Hive.MCP.Components.Schemas.project(),
          "webhook" => Hive.MCP.Components.Schemas.webhook(),
          "webhook_url" => %{"type" => "string"}
        },
        ["project", "webhook", "webhook_url"]
      )

  alias Hive.Auth
  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.MCP.Tool
  alias Hive.Projects
  alias Hive.Projects.Webhooks
  alias HiveWeb.Endpoint

  @impl EMCP.Tool
  def description,
    do: "Create a project webhook and return its one-time URL. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"project_id" => project_id} = args) do
    user = conn.assigns[:current_user]

    with true <- Auth.member?(user),
         {:ok, project} <- Projects.fetch_visible_project(project_id, user) do
      attrs = Map.take(args, ["name", "source"])

      case Webhooks.create(project, attrs) do
        {:ok, {webhook, token}} ->
          json_response(%{
            project: project.id |> Projects.get_project!() |> ProjectTool.project_json(),
            webhook: ProjectTool.webhook_json(webhook),
            webhook_url: webhook_ingest_url(project.id, webhook.source, token)
          })

        {:error, changeset} ->
          json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
      end
    else
      false -> json_response(%{error: "unauthorized"})
      {:error, :not_found} -> json_response(%{error: "not_found"})
    end
  end

  defp webhook_ingest_url(project_id, source, token) do
    Endpoint.url() <> "/webhooks/projects/#{project_id}/#{source}/#{token}"
  end
end

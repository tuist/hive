defmodule Hive.MCP.Components.Tools.StartGrafanaAlertCodingRun do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "start_grafana_alert_coding_run",
    title: "Start Grafana Alert Coding Run",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["alert_id", "repository_id"],
      "properties" => %{
        "alert_id" => %{
          "type" => "string",
          "description" => "Grafana alert identifier or grafana_alert:<identifier>."
        },
        "repository_id" => %{
          "type" => "string",
          "description" => "Identifier of a repository linked to the alert's project."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"coding_run" => Hive.MCP.Components.Schemas.coding_run()},
        ["coding_run"]
      )

  alias Hive.Auth
  alias Hive.Forage
  alias Hive.Forage.CodingRuns
  alias Hive.MCP.Components.Tools.CodingRuns, as: CodingRunTool

  @impl EMCP.Tool
  def description do
    "Start an isolated coding run for a Grafana alert. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, %{"alert_id" => alert_id, "repository_id" => repository_id}) do
    user = conn.assigns[:current_user]

    if Auth.member?(user) do
      alert_id = String.replace_prefix(alert_id, "grafana_alert:", "")
      start_run(alert_id, repository_id, user)
    else
      json_response(%{error: "unauthorized"})
    end
  end

  defp start_run(alert_id, repository_id, user) do
    case Forage.get_grafana_alert(alert_id) do
      nil ->
        json_response(%{error: "not_found"})

      alert ->
        create_run(alert, repository_id, user)
    end
  end

  defp create_run(alert, repository_id, user) do
    case CodingRuns.create_for_grafana_alert(alert, repository_id, user) do
      {:ok, run} -> json_response(%{coding_run: CodingRunTool.coding_run_json(run)})
      {:error, reason} -> json_response(%{error: Atom.to_string(reason)})
    end
  end
end

defmodule Hive.MCP.Components.Tools.StartGrafanaAlertFlight do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "start_grafana_alert_flight",
    title: "Start Grafana Alert Flight",
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
        },
        "objective" => %{
          "type" => "string",
          "enum" => ["investigate", "reproduce", "fix"],
          "description" => "The objective the Flight should pursue. Defaults to investigate."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"flight" => Hive.MCP.Components.Schemas.flight()},
        ["flight"]
      )

  alias Hive.Auth
  alias Hive.Flights
  alias Hive.Forage

  @impl EMCP.Tool
  def description do
    "Start an isolated Flight for a Grafana alert. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, %{"alert_id" => alert_id, "repository_id" => repository_id} = args) do
    user = conn.assigns[:current_user]

    if Auth.member?(user) do
      alert_id = String.replace_prefix(alert_id, "grafana_alert:", "")
      start_run(alert_id, repository_id, args["objective"] || "investigate", user)
    else
      json_response(%{error: "unauthorized"})
    end
  end

  defp start_run(alert_id, repository_id, objective, user) do
    case Forage.get_grafana_alert(alert_id) do
      nil ->
        json_response(%{error: "not_found"})

      alert ->
        create_run(alert, repository_id, objective, user)
    end
  end

  defp create_run(alert, repository_id, objective, user) do
    case Flights.start_for_grafana_alert(alert, repository_id, user,
           objective: objective,
           trigger: %{"source" => "mcp"}
         ) do
      {:ok, flight} ->
        flight = Flights.get_flight_for_user(flight.id, user)
        json_response(%{flight: Flights.serialize(flight)})

      {:error, reason} ->
        json_response(%{error: Atom.to_string(reason)})
    end
  end
end

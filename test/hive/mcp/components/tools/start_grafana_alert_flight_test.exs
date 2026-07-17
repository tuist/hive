defmodule Hive.MCP.Components.Tools.StartGrafanaAlertFlightTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Flights
  alias Hive.Flights.Flight
  alias Hive.Forage.Grafana
  alias Hive.MCP.Components.Tools.StartGrafanaAlertFlight
  alias Hive.Projects
  alias Hive.Projects.Webhooks

  test "starts a Flight for an organization member" do
    user = mcp_user("flight-member@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{owner: "tuist", name: unique_repo()})

    {:ok, {webhook, _token}} =
      Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    {:ok, [alert]} = Grafana.ingest(project, webhook, alert_payload())

    flight =
      %Flight{}
      |> Flight.changeset(%{
        forage_item_id: "grafana_alert:#{alert.id}",
        status: :queued,
        runner: "kubernetes",
        repository_full_name: "tuist/#{repository.name}",
        repository_id: repository.id,
        requested_by_id: user.id,
        input: %{"title" => "High latency"}
      })
      |> Repo.insert!()

    expect(Flights, :start_for_grafana_alert, fn fetched_alert, repository_id, caller, opts ->
      assert fetched_alert.id == alert.id
      assert repository_id == repository.id
      assert caller.id == user.id
      assert opts[:objective] == "reproduce"
      assert opts[:trigger] == %{"source" => "mcp"}
      {:ok, flight}
    end)

    response =
      user
      |> mcp_conn()
      |> StartGrafanaAlertFlight.call(%{
        "alert_id" => "grafana_alert:#{alert.id}",
        "repository_id" => repository.id,
        "objective" => "reproduce"
      })
      |> response_json()

    assert response["flight"]["id"] == flight.id
    assert response["flight"]["status"] == "queued"
    assert response["flight"]["forage_item"]["id"] == "grafana_alert:#{alert.id}"
  end

  test "rejects collaborators" do
    user = mcp_user("flight-collaborator@example.com", :collaborator)

    response =
      user
      |> mcp_conn()
      |> StartGrafanaAlertFlight.call(%{
        "alert_id" => Ecto.UUID.generate(),
        "repository_id" => Ecto.UUID.generate()
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end

  defp unique_repo, do: "hive-#{System.unique_integer([:positive])}"

  defp alert_payload do
    %{
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => "mcp-#{System.unique_integer([:positive])}",
          "labels" => %{"alertname" => "HighLatency"},
          "annotations" => %{"summary" => "High latency"}
        }
      ]
    }
  end
end

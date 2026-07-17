defmodule Hive.MCP.Components.Tools.StartForageItemFlightTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Flights
  alias Hive.Flights.Flight
  alias Hive.Forage.Grafana
  alias Hive.MCP.Components.Tools.StartForageItemFlight
  alias Hive.Projects
  alias Hive.Projects.Webhooks

  test "starts an objective-specific Flight for a supported Forage item" do
    user = mcp_user("forage-flight-member@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Forage Flight")})

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
        objective: :reproduce,
        runner: "kubernetes",
        repository_full_name: "tuist/#{repository.name}",
        repository_id: repository.id,
        requested_by_id: user.id,
        trigger: %{"source" => "mcp"},
        input: %{"title" => "High latency"}
      })
      |> Repo.insert!()

    expect(Flights, :start_for_item, fn item, repository_id, caller, opts ->
      assert item.id == "grafana_alert:#{alert.id}"
      assert repository_id == repository.id
      assert caller.id == user.id
      assert opts[:objective] == "reproduce"
      assert opts[:trigger] == %{"source" => "mcp"}
      {:ok, flight}
    end)

    response =
      user
      |> mcp_conn()
      |> StartForageItemFlight.call(%{
        "forage_item_id" => "grafana_alert:#{alert.id}",
        "repository_id" => repository.id,
        "objective" => "reproduce"
      })
      |> response_json()

    assert response["flight"]["id"] == flight.id
    assert response["flight"]["objective"] == "reproduce"
    assert response["flight"]["trigger"] == %{"source" => "mcp"}
  end

  test "rejects collaborators" do
    user = mcp_user("forage-flight-collaborator@example.com", :collaborator)

    response =
      user
      |> mcp_conn()
      |> StartForageItemFlight.call(%{
        "forage_item_id" => "grafana_alert:#{Ecto.UUID.generate()}",
        "repository_id" => Ecto.UUID.generate(),
        "objective" => "investigate"
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
          "fingerprint" => "generic-mcp-#{System.unique_integer([:positive])}",
          "labels" => %{"alertname" => "HighLatency"},
          "annotations" => %{"summary" => "High latency"}
        }
      ]
    }
  end
end

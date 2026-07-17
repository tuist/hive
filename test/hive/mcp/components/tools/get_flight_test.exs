defmodule Hive.MCP.Components.Tools.GetFlightTest do
  use Hive.MCPToolCase

  alias Hive.Flights.Flight
  alias Hive.MCP.Components.Tools.GetFlight
  alias Hive.Projects

  test "returns a Flight with its portable session to an organization member" do
    user = mcp_user("get-flight@example.com", :member)
    repository = repository()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    flight =
      %Flight{}
      |> Flight.changeset(%{
        forage_item_id: "grafana_alert:missing-alert",
        status: :succeeded,
        runner: "microsandbox",
        repository_full_name: "tuist/#{repository.name}",
        repository_id: repository.id,
        requested_by_id: user.id,
        input: %{"title" => "High latency"},
        session: %{
          "source" => %{"base_revision" => "abc123"},
          "messages" => [%{"role" => "assistant", "content" => "Handled it."}]
        },
        result: %{"type" => "pull_request"},
        started_at: now,
        completed_at: now
      })
      |> Repo.insert!()

    response =
      user
      |> mcp_conn()
      |> GetFlight.call(%{"id" => flight.id})
      |> response_json()

    assert response["flight"]["status"] == "succeeded"
    assert response["flight"]["session"]["source"]["base_revision"] == "abc123"
    assert [%{"content" => "Handled it."}] = response["flight"]["session"]["messages"]
  end

  test "hides Flights from collaborators" do
    user = mcp_user("missing-flight@example.com", :collaborator)

    response =
      user
      |> mcp_conn()
      |> GetFlight.call(%{"id" => Ecto.UUID.generate()})
      |> response_json()

    assert response == %{"error" => "not_found"}
  end

  defp repository do
    {:ok, project} = Projects.create_project(%{name: unique_name("Flight")})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{
        owner: "tuist",
        name: "hive-#{System.unique_integer([:positive])}"
      })

    repository
  end
end

defmodule Hive.MCP.Components.Tools.ListFlightsTest do
  use Hive.MCPToolCase

  alias Hive.Flights.Flight
  alias Hive.MCP.Components.Tools.ListFlights
  alias Hive.Projects

  test "lists filtered Flights without embedding their sessions" do
    user = mcp_user("list-flights@example.com", :member)
    repository = repository()
    insert_flight(repository, user, :succeeded, :investigate, "First alert")
    insert_flight(repository, user, :failed, :reproduce, "Second alert")

    response =
      user
      |> mcp_conn()
      |> ListFlights.call(%{
        "status" => "failed",
        "objective" => "reproduce",
        "page_size" => 10
      })
      |> response_json()

    assert [%{"status" => "failed", "input" => %{"title" => "Second alert"}} = flight] =
             response["flights"]

    assert flight["session"] == nil
    assert flight["objective"] == "reproduce"
    assert response["pagination"]["total_count"] == 1
  end

  test "rejects collaborators" do
    user = mcp_user("list-flights-collaborator@example.com", :collaborator)

    response = user |> mcp_conn() |> ListFlights.call(%{}) |> response_json()

    assert response == %{"error" => "forbidden"}
  end

  defp insert_flight(repository, user, status, objective, title) do
    %Flight{}
    |> Flight.changeset(%{
      forage_item_id: "grafana_alert:#{Ecto.UUID.generate()}",
      status: status,
      objective: objective,
      runner: "microsandbox",
      repository_full_name: "tuist/#{repository.name}",
      repository_id: repository.id,
      requested_by_id: user.id,
      input: %{"title" => title},
      session: %{"messages" => []},
      error: if(status == :failed, do: "Sandbox stopped", else: nil)
    })
    |> Repo.insert!()
  end

  defp repository do
    {:ok, project} = Projects.create_project(%{name: unique_name("Flights")})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{
        owner: "tuist",
        name: "hive-#{System.unique_integer([:positive])}"
      })

    repository
  end
end

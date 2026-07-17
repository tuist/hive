defmodule HiveWeb.FlightLive.IndexTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Flights.Flight
  alias Hive.Projects
  alias Hive.Repo

  test "lists and searches Flights for organization members", %{conn: conn} do
    {conn, user} = sign_in(conn, "flights-index@example.com")
    repository = repository()
    flight = insert_flight(repository, user, "High latency", :succeeded)
    insert_flight(repository, user, "Worker crash", :failed)

    {:ok, view, html} = live(conn, ~p"/flights")

    assert html =~ "Execution history"
    assert html =~ "High latency"
    assert html =~ "Worker crash"
    assert html =~ "Investigate"
    assert has_element?(view, "#flights-table")
    assert has_element?(view, "a[href='/flights/#{flight.id}']")
    assert has_element?(view, "#flights-feeds")

    view
    |> form("#flights-search-form", search: %{query: "High latency"})
    |> render_change()

    assert_patch(view, ~p"/flights?q=High+latency")
    assert render(view) =~ "High latency"
    refute render(view) =~ "Worker crash"
  end

  test "redirects collaborators away from Flights", %{conn: conn} do
    {conn, user} = sign_in(conn, "flights-collaborator@example.com")
    {:ok, _user} = Hive.Accounts.update_user_role(user, :collaborator)

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/flights")
  end

  defp insert_flight(repository, user, title, status) do
    %Flight{}
    |> Flight.changeset(%{
      forage_item_id: "manual:#{Ecto.UUID.generate()}",
      status: status,
      runner: "microsandbox",
      repository_full_name: "tuist/#{repository.name}",
      repository_id: repository.id,
      requested_by_id: user.id,
      input: %{"title" => title},
      result: %{"summary" => "Handled #{title}"}
    })
    |> Repo.insert!()
  end

  defp repository do
    {:ok, project} = Projects.create_project(%{name: "Flights index"})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{
        owner: "tuist",
        name: "hive-#{System.unique_integer([:positive])}"
      })

    repository
  end
end

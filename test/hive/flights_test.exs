defmodule Hive.FlightsTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Flights
  alias Hive.Flights.Flight
  alias Hive.Forage.Grafana
  alias Hive.Projects
  alias Hive.Projects.Webhooks

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "flights-#{suffix}@example.com",
        provider: "test",
        provider_uid: "flights-#{suffix}"
      })

    {:ok, user} = Accounts.update_user_role(user, :member)
    {:ok, project} = Projects.create_project(%{name: "Flights #{suffix}"})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{owner: "tuist", name: "hive-#{suffix}"})

    {:ok, {webhook, _token}} =
      Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    {:ok, [alert]} = Grafana.ingest(project, webhook, alert_payload("flight-#{suffix}"))

    {:ok, user: user, repository: repository, alert: alert}
  end

  test "lists Flights with their Forage items and supports filters", ctx do
    succeeded =
      ctx
      |> insert_flight(:succeeded, "High latency", "Latency was bounded")
      |> Flight.changeset(%{
        objective: :reproduce,
        objective_outcome: :not_reproduced,
        trigger: %{"source" => "dashboard"}
      })
      |> Repo.update!()

    _failed = insert_flight(ctx, :failed, "Worker crash", nil, "Sandbox stopped")

    {flights, pagination} =
      Flights.list_flights_for_user(ctx.user,
        status: "succeeded",
        objective: "reproduce",
        objective_outcome: "not_reproduced",
        query: "latency"
      )

    assert [flight] = flights
    assert flight.id == succeeded.id
    assert flight.forage_item.id == "grafana_alert:#{ctx.alert.id}"
    assert flight.forage_item.title == "High latency"
    assert flight.session == nil
    assert flight.objective == :reproduce
    assert flight.objective_outcome == :not_reproduced
    assert pagination.total_count == 1

    assert {[], %{total_count: 0}} =
             Flights.list_flights_for_user(%{ctx.user | role: :collaborator})
  end

  test "serializes continuation context only when requested", ctx do
    flight = insert_flight(ctx, :succeeded, "High latency", "Handled")
    flight = Flights.get_flight_for_user(flight.id, ctx.user)

    assert Flights.serialize(flight).session["source"]["base_revision"] == "abc123"
    assert Flights.serialize(flight).forage_item.id == "grafana_alert:#{ctx.alert.id}"
    assert Flights.serialize(flight).objective == "investigate"
    assert Flights.serialize(flight).trigger == %{}
    assert Flights.serialize(flight, include_session?: false).session == nil
  end

  test "paginates the durable history", ctx do
    for index <- 1..11 do
      insert_flight(
        ctx,
        :succeeded,
        "Alert #{index}",
        "Handled",
        nil,
        "manual:#{Ecto.UUID.generate()}"
      )
    end

    {first_page, first_meta} = Flights.list_flights_for_user(ctx.user, page: 1, page_size: 10)
    {second_page, second_meta} = Flights.list_flights_for_user(ctx.user, page: 2, page_size: 10)

    assert length(first_page) == 10
    assert length(second_page) == 1
    assert first_meta.has_next_page?
    assert second_meta.has_previous_page?
    assert first_meta.total_count == 11
  end

  defp insert_flight(ctx, status, title, summary, error \\ nil, forage_item_id \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Flight{}
    |> Flight.changeset(%{
      forage_item_id: forage_item_id || "grafana_alert:#{ctx.alert.id}",
      status: status,
      runner: "microsandbox",
      runner_id: "sandbox-123",
      repository_full_name: "tuist/#{ctx.repository.name}",
      repository_id: ctx.repository.id,
      requested_by_id: ctx.user.id,
      input: %{"title" => title},
      session: %{
        "source" => %{"base_branch" => "main", "base_revision" => "abc123"},
        "messages" => [%{"role" => "assistant", "content" => "Handled it."}]
      },
      result: summary && %{"type" => "report", "summary" => summary},
      error: error,
      started_at: DateTime.add(now, -60, :second),
      completed_at: now
    })
    |> Repo.insert!()
  end

  defp alert_payload(fingerprint) do
    %{
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => fingerprint,
          "labels" => %{"alertname" => "HighLatency"},
          "annotations" => %{"summary" => "High latency"}
        }
      ]
    }
  end
end

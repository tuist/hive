defmodule Hive.Slack.Workers.UpdateFlightMessage do
  @moduledoc """
  Keeps the Slack message that started a Flight aligned with its latest state.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: 60, states: :incomplete]

  alias Hive.Flights
  alias Hive.Slack.FlightMessages

  # The status is part of the args so uniqueness keys on it: each state
  # transition enqueues a distinct job instead of being deduplicated against a
  # still-pending update for an earlier state. The worker always reads the
  # latest flight state, so the value only discriminates transitions.
  def enqueue(flight_id, status) when is_binary(flight_id) do
    %{"flight_id" => flight_id, "status" => to_string(status)}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"flight_id" => flight_id}}) do
    case Flights.get_flight(flight_id) do
      nil -> :ok
      flight -> FlightMessages.update(flight)
    end
  end
end

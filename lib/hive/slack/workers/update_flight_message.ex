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

  def enqueue(flight_id) when is_binary(flight_id) do
    %{"flight_id" => flight_id}
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

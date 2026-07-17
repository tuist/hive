defmodule HiveWeb.API.FlightController do
  use HiveWeb, :controller

  alias Hive.Flights
  alias Hive.Flights.Policy
  alias HiveWeb.Utilities.Query

  def index(conn, params) do
    user = conn.assigns.current_user

    if Policy.authorize?(:flight_read, user, nil) do
      {flights, pagination} =
        Flights.list_flights_for_user(user,
          page: Query.parse_page(params["page"]),
          page_size: page_size(params["page_size"]),
          query: Query.present_string(params["q"]),
          status: Query.present_string(params["status"]),
          objective: Query.present_string(params["objective"]),
          objective_outcome: Query.present_string(params["outcome"]),
          runner: Query.present_string(params["runner"]),
          repository: Query.present_string(params["repository"])
        )

      json(conn, %{
        data: Enum.map(flights, &Flights.serialize(&1, include_session?: false)),
        pagination: pagination
      })
    else
      conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def show(conn, %{"id" => id}) do
    case Flights.get_flight_for_user(id, conn.assigns.current_user) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
      flight -> json(conn, %{data: Flights.serialize(flight)})
    end
  end

  defp page_size(value) when is_binary(value) do
    case Integer.parse(value) do
      {size, ""} when size > 0 -> min(size, 100)
      _other -> 20
    end
  end

  defp page_size(value) when is_integer(value) and value > 0, do: min(value, 100)
  defp page_size(_value), do: 20
end

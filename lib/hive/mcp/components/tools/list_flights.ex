defmodule Hive.MCP.Components.Tools.ListFlights do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_flights",
    title: "List Flights",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" => "Search the signal title, result, repository, or error."
        },
        "status" => %{
          "type" => "string",
          "enum" => Enum.map(Hive.Flights.statuses(), &Atom.to_string/1)
        },
        "objective" => %{
          "type" => "string",
          "enum" => Enum.map(Hive.Flights.objectives(), &Atom.to_string/1)
        },
        "outcome" => %{
          "type" => "string",
          "enum" => Enum.map(Hive.Flights.objective_outcomes(), &Atom.to_string/1)
        },
        "runner" => %{"type" => "string"},
        "repository" => %{"type" => "string"},
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "flights" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Schemas.flight()
          },
          "pagination" => Hive.MCP.Components.Schemas.pagination()
        },
        ["flights", "pagination"]
      )

  alias Hive.Flights
  alias Hive.Flights.Policy

  @impl EMCP.Tool
  def description do
    "List durable agent Flights and the Forage items that prompted them. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, args) do
    user = conn.assigns[:current_user]

    if Policy.authorize?(:flight_read, user, nil) do
      {flights, pagination} = Flights.list_flights_for_user(user, list_opts(args))

      json_response(%{
        flights: Enum.map(flights, &Flights.serialize(&1, include_session?: false)),
        pagination: pagination
      })
    else
      json_response(%{error: "forbidden"})
    end
  end

  defp list_opts(args) do
    [
      page: positive_integer(args["page"], 1),
      page_size: min(positive_integer(args["page_size"], 20), 100),
      query: present(args["query"]),
      status: present(args["status"]),
      objective: present(args["objective"]),
      objective_outcome: present(args["outcome"]),
      runner: present(args["runner"]),
      repository: present(args["repository"])
    ]
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present(_value), do: nil
end

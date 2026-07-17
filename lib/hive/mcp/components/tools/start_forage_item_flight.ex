defmodule Hive.MCP.Components.Tools.StartForageItemFlight do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "start_forage_item_flight",
    title: "Start Forage Item Flight",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["forage_item_id", "repository_id", "objective"],
      "properties" => %{
        "forage_item_id" => %{
          "type" => "string",
          "description" => "Forage item identifier."
        },
        "repository_id" => %{
          "type" => "string",
          "description" => "Identifier of a repository linked to the Forage item."
        },
        "objective" => %{
          "type" => "string",
          "enum" => ["investigate", "reproduce", "fix"],
          "description" => "The objective the Flight should pursue."
        },
        "parent_flight_id" => %{
          "type" => "string",
          "description" => "Optional earlier Flight whose work this Flight continues."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"flight" => Hive.MCP.Components.Schemas.flight()},
        ["flight"]
      )

  alias Hive.Auth
  alias Hive.Flights
  alias Hive.Forage

  @impl EMCP.Tool
  def description do
    "Start an isolated Flight for a supported Forage item. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, args) do
    user = conn.assigns[:current_user]

    if Auth.member?(user) do
      start_flight(args, user)
    else
      json_response(%{error: "unauthorized"})
    end
  end

  defp start_flight(args, user) do
    with {:ok, item} <- Forage.get_item_for_user(args["forage_item_id"], user),
         {:ok, flight} <-
           Flights.start_for_item(item, args["repository_id"], user,
             objective: args["objective"],
             parent_flight_id: args["parent_flight_id"],
             trigger: %{"source" => "mcp"}
           ) do
      flight = Flights.get_flight_for_user(flight.id, user)
      json_response(%{flight: Flights.serialize(flight)})
    else
      {:error, :not_found} -> json_response(%{error: "not_found"})
      {:error, reason} -> json_response(%{error: Atom.to_string(reason)})
    end
  end
end

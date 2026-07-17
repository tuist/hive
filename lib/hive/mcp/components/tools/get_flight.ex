defmodule Hive.MCP.Components.Tools.GetFlight do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_flight",
    title: "Get Flight",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "Flight identifier."}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"flight" => Hive.MCP.Components.Schemas.flight()},
        ["flight"]
      )

  alias Hive.Flights

  @impl EMCP.Tool
  def description do
    "Fetch one Flight with its Forage item, outcome, source revision, and portable agent session. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    case Flights.get_flight_for_user(id, conn.assigns[:current_user]) do
      nil -> json_response(%{error: "not_found"})
      flight -> json_response(%{flight: Flights.serialize(flight)})
    end
  end
end

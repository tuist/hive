defmodule Hive.MCP.Components.Tools.ListDropDigests do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_drop_digests",
    title: "List Drop Digests",
    schema: %{
      "type" => "object",
      "properties" => %{
        "limit" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 100,
          "description" => "Maximum number of weekly editions to return."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "digests" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Tools.DropDigests.digest_schema()
          }
        },
        ["digests"]
      )

  alias Hive.Drops.WeeklyDigests
  alias Hive.MCP.Components.Tools.DropDigests

  @impl EMCP.Tool
  def description, do: "List published weekly Drops digests, newest first."

  @impl EMCP.Tool
  def call(_conn, args) do
    limit = Map.get(args, "limit", 52)

    json_response(%{
      digests:
        WeeklyDigests.list_published(limit: limit)
        |> Enum.map(&DropDigests.digest_json/1)
    })
  end
end

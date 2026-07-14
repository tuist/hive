defmodule Hive.MCP.Components.Tools.GetDropDigest do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_drop_digest",
    title: "Get Drop Digest",
    schema: %{
      "type" => "object",
      "required" => ["week"],
      "properties" => %{
        "week" => %{
          "type" => "string",
          "description" => "Week start date, shared digest URL, or latest."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"digest" => Hive.MCP.Components.Tools.DropDigests.digest_schema()},
        ["digest"]
      )

  alias Hive.Drops.WeeklyDigests
  alias Hive.MCP.Components.Tools.DropDigests

  @impl EMCP.Tool
  def description, do: "Fetch one narrated weekly Drops digest with its full body."

  @impl EMCP.Tool
  def call(_conn, %{"week" => week}) do
    case WeeklyDigests.fetch_published(week) do
      {:ok, digest} -> json_response(%{digest: DropDigests.digest_json(digest)})
      {:error, :not_found} -> json_response(%{error: "not_found"})
    end
  end
end

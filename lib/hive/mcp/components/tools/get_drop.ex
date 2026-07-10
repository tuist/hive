defmodule Hive.MCP.Components.Tools.GetDrop do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_drop",
    title: "Get Drop",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{
          "oneOf" => [%{"type" => "integer"}, %{"type" => "string"}],
          "description" => "Drop public number or /drops/:number URL."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"drop" => Hive.MCP.Components.Tools.Drops.drop_schema()},
        ["drop"]
      )

  alias Hive.Drops
  alias Hive.MCP.Components.Tools.Drops, as: DropTool

  @impl EMCP.Tool
  def description, do: "Fetch one drop with its full body, link, and domain context."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    case Drops.fetch_visible_drop(id, conn.assigns[:current_user]) do
      {:ok, drop} -> json_response(%{drop: DropTool.drop_json(drop)})
      {:error, :not_found} -> json_response(%{error: "not_found"})
    end
  end
end

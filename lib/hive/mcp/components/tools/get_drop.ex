defmodule Hive.MCP.Components.Tools.GetDrop do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_drop",
    title: "Get Drop",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "Drop UUID."}
      }
    }

  alias Hive.Drops
  alias Hive.MCP.Components.Tools.Drops, as: DropTool
  alias Hive.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Fetch one drop with its full body, link, and domain context."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    case Drops.fetch_visible_drop(id, conn.assigns[:current_user]) do
      {:ok, drop} -> Tool.json_response(%{drop: DropTool.drop_json(drop)})
      {:error, :not_found} -> Tool.json_response(%{error: "not_found"})
    end
  end
end

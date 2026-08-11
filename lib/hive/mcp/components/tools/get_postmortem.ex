defmodule Hive.MCP.Components.Tools.GetPostmortem do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_postmortem",
    title: "Get Postmortem",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Postmortem identifier, public number, or shared postmortem address."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"postmortem" => Hive.MCP.Components.Schemas.postmortem()},
        ["postmortem"]
      )

  alias Hive.MCP.Components.Tools.Postmortems, as: PostmortemTool
  alias Hive.Postmortems

  @impl EMCP.Tool
  def description, do: "Fetch one visible postmortem with its domains and action items."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    case Postmortems.fetch_visible_postmortem_by_reference(id, conn.assigns[:current_user]) do
      {:ok, postmortem} ->
        json_response(%{postmortem: PostmortemTool.postmortem_json(postmortem)})

      {:error, :not_found} ->
        json_response(%{error: "not_found"})
    end
  end
end

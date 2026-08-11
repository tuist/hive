defmodule Hive.MCP.Components.Tools.ListPostmortems do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_postmortems",
    title: "List Postmortems",
    schema: %{"type" => "object", "properties" => %{}},
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "postmortems" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Schemas.postmortem()
          }
        },
        ["postmortems"]
      )

  alias Hive.MCP.Components.Tools.Postmortems, as: PostmortemTool
  alias Hive.Postmortems

  @impl EMCP.Tool
  def description, do: "List the Hive postmortems visible to the caller."

  @impl EMCP.Tool
  def call(conn, _args) do
    postmortems =
      conn.assigns[:current_user]
      |> Postmortems.list_postmortems()
      |> Enum.map(&PostmortemTool.postmortem_json/1)

    json_response(%{postmortems: postmortems})
  end
end

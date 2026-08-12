defmodule Hive.MCP.Components.Tools.UpdatePostmortem do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "update_postmortem",
    title: "Update Postmortem",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Postmortem identifier, public number, or shared postmortem address."
        },
        "body" => %{"type" => "string", "description" => "Complete postmortem in Markdown."},
        "visibility" => %{"type" => "string", "enum" => ["public", "private"]},
        "domain_ids" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Domain identifiers to associate with the postmortem."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"postmortem" => Hive.MCP.Components.Schemas.postmortem()},
        ["postmortem"]
      )

  alias Hive.MCP.Components.Tools.Postmortems, as: PostmortemTool
  alias Hive.MCP.Tool
  alias Hive.Postmortems

  @impl EMCP.Tool
  def description, do: "Update a Hive postmortem. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"id" => id} = args) do
    user = conn.assigns[:current_user]

    case Postmortems.fetch_visible_postmortem_by_reference(id, user) do
      {:ok, postmortem} -> update(postmortem, user, args)
      {:error, :not_found} -> json_response(%{error: "not_found"})
    end
  end

  defp update(postmortem, user, args) do
    attrs = Map.take(args, ["body", "visibility", "domain_ids"])

    case Postmortems.update_postmortem(postmortem, attrs, user) do
      {:ok, postmortem} ->
        postmortem = Postmortems.get_postmortem!(postmortem.id)
        json_response(%{postmortem: PostmortemTool.postmortem_json(postmortem)})

      {:error, :unauthorized} ->
        json_response(%{error: "unauthorized"})

      {:error, changeset} ->
        json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
    end
  end
end

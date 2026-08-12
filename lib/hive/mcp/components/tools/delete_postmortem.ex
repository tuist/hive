defmodule Hive.MCP.Components.Tools.DeletePostmortem do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "delete_postmortem",
    title: "Delete Postmortem",
    read_only_hint: false,
    destructive_hint: true,
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
        %{"deleted_postmortem" => Hive.MCP.Components.Schemas.postmortem()},
        ["deleted_postmortem"]
      )

  alias Hive.Auth
  alias Hive.MCP.Components.Tools.Postmortems, as: PostmortemTool
  alias Hive.MCP.Tool
  alias Hive.Postmortems

  @impl EMCP.Tool
  def description, do: "Delete a Hive postmortem and its action items. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]

    if Auth.member?(user) do
      delete(user, id)
    else
      json_response(%{error: "unauthorized"})
    end
  end

  defp delete(user, id) do
    case Postmortems.fetch_visible_postmortem_by_reference(id, user) do
      {:ok, postmortem} ->
        deleted_postmortem = PostmortemTool.postmortem_json(postmortem)

        case Postmortems.delete_postmortem(postmortem, user) do
          {:ok, _postmortem} ->
            json_response(%{deleted_postmortem: deleted_postmortem})

          {:error, :unauthorized} ->
            json_response(%{error: "unauthorized"})

          {:error, changeset} ->
            json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
        end

      {:error, :not_found} ->
        json_response(%{error: "not_found"})
    end
  end
end

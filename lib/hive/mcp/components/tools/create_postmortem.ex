defmodule Hive.MCP.Components.Tools.CreatePostmortem do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "create_postmortem",
    title: "Create Postmortem",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["body"],
      "properties" => %{
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
  def description, do: "Publish a Hive postmortem. Organization member only."

  @impl EMCP.Tool
  def call(conn, args) do
    attrs = Map.take(args, ["body", "visibility", "domain_ids"])

    case Postmortems.publish_postmortem(attrs, conn.assigns[:current_user]) do
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

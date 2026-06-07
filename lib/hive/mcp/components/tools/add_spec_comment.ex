defmodule Hive.MCP.Components.Tools.AddSpecComment do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "add_spec_comment",
    title: "Add Spec Comment",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["spec_id", "body"],
      "properties" => %{
        "spec_id" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "author_name" => %{"type" => "string"}
      }
    }

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description, do: "Add a comment to a Hive spec."

  @impl EMCP.Tool
  def call(conn, %{"spec_id" => spec_id} = args) do
    spec = Specs.get_spec!(spec_id)

    case Specs.add_comment(
           spec,
           Map.take(args, ["body", "author_name"]),
           conn.assigns.current_user
         ) do
      {:ok, _comment} ->
        Tool.json_response(%{spec: SpecTool.spec_json(Specs.get_spec!(spec.id))})

      {:error, changeset} ->
        Tool.json_response(%{error: "invalid", details: errors(changeset)})
    end
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end

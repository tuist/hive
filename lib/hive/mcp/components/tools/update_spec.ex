defmodule Hive.MCP.Components.Tools.UpdateSpec do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "update_spec",
    title: "Update Spec",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["id", "expected_revision"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "summary" => %{
          "type" => "string",
          "description" =>
            "Short spec description for summaries and OpenGraph cards. Do not use em dashes."
        },
        "status" => %{"type" => "string"},
        "expected_revision" => %{"type" => "integer"}
      }
    }

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description do
    "Update a Hive spec after checking the expected revision. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, %{"id" => id, "expected_revision" => expected_revision} = args) do
    spec = Specs.get_spec!(id)

    if spec.lock_version == expected_revision do
      update(conn, spec, args)
    else
      Tool.json_response(%{
        error: "stale_revision",
        current_revision: spec.lock_version,
        spec: SpecTool.spec_json(spec)
      })
    end
  end

  defp update(conn, spec, args) do
    attrs = Map.take(args, ["title", "body", "summary", "status"])

    case Specs.update_spec(spec, attrs, conn.assigns.current_user) do
      {:ok, spec} ->
        Tool.json_response(%{spec: SpecTool.spec_json(Specs.get_spec!(spec.id))})

      {:error, :unauthorized} ->
        Tool.json_response(%{error: "unauthorized"})

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

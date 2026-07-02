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
        "id" => %{
          "type" => "string",
          "description" => "Spec UUID, public number, or /specs/:number URL."
        },
        "title" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "summary" => %{
          "type" => "string",
          "description" =>
            "Short spec description for summaries and OpenGraph cards. Do not use em dashes."
        },
        "status" => %{"type" => "string"},
        "visibility" => %{
          "type" => "string",
          "description" => "Spec visibility. Use public or private."
        },
        "domain_ids" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Domain IDs to associate with the spec."
        },
        "expected_revision" => %{"type" => "integer"}
      }
    }

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description do
    "Update a Hive spec after checking the expected revision. Organization member only. When the revision is a substantive rewrite, fetch the `write_spec` MCP prompt first so the body follows the house style."
  end

  @impl EMCP.Tool
  def call(conn, %{"id" => id, "expected_revision" => expected_revision} = args) do
    spec = Specs.get_spec_by_reference!(id)

    cond do
      not Specs.can_view?(spec, conn.assigns.current_user) ->
        Tool.json_response(%{error: "not_found"})

      spec.lock_version == expected_revision ->
        update(conn, spec, args)

      true ->
        Tool.json_response(%{
          error: "stale_revision",
          current_revision: spec.lock_version,
          spec: SpecTool.spec_json(spec)
        })
    end
  end

  defp update(conn, spec, args) do
    attrs = Map.take(args, ["title", "body", "summary", "status", "visibility", "domain_ids"])

    case Specs.update_spec(spec, attrs, conn.assigns.current_user) do
      {:ok, spec} ->
        Tool.json_response(%{spec: SpecTool.spec_json(Specs.get_spec!(spec.id))})

      {:error, :unauthorized} ->
        Tool.json_response(%{error: "unauthorized"})

      {:error, :locked} ->
        Tool.json_response(%{
          error: "locked",
          message: "This spec is being written by another request. Try again in a moment."
        })

      {:error, changeset} ->
        Tool.json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
    end
  end
end

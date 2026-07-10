defmodule Hive.MCP.Components.Tools.CreateSpec do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "create_spec",
    title: "Create Spec",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["title", "body", "project_id"],
      "properties" => %{
        "title" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "summary" => %{
          "type" => "string",
          "description" =>
            "Short spec description for summaries and OpenGraph cards. Do not use em dashes."
        },
        "status" => %{"type" => "string"},
        "project_id" => %{
          "type" => "string",
          "description" => "Project identifier the spec belongs to."
        },
        "visibility_override" => %{
          "type" => "string",
          "enum" => ["private"],
          "description" => "Optional private override. Omit it to inherit project visibility."
        },
        "domain_ids" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Domain IDs to associate with the spec."
        },
        "source_feature_request_id" => %{"type" => "string"}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"spec" => Hive.MCP.Components.Tools.Specs.spec_schema()},
        ["spec"],
        %{"message" => %{"type" => "string"}}
      )

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description do
    "Create a Hive spec, optionally linked to a feature request forage item. Organization member only. When drafting from scratch, fetch the `write_spec` MCP prompt first so the body follows the house style."
  end

  @impl EMCP.Tool
  def call(conn, args) do
    attrs =
      args
      |> Map.take([
        "title",
        "body",
        "summary",
        "status",
        "project_id",
        "visibility_override",
        "domain_ids",
        "source_feature_request_id"
      ])
      |> Map.put_new("status", "draft")

    case Specs.create_spec(attrs, conn.assigns.current_user) do
      {:ok, spec} ->
        json_response(%{
          spec: spec.id |> Specs.get_spec!() |> SpecTool.spec_json()
        })

      {:error, :unauthorized} ->
        json_response(%{error: "unauthorized"})

      {:error, :locked} ->
        json_response(%{
          error: "locked",
          message: "A spec write is currently in progress. Try again in a moment."
        })

      {:error, changeset} ->
        json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
    end
  end
end

defmodule Hive.MCP.Components.Tools.CreateSpec do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "create_spec",
    title: "Create Spec",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["title", "body"],
      "properties" => %{
        "title" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "summary" => %{
          "type" => "string",
          "description" =>
            "Short spec description for summaries and OpenGraph cards. Do not use em dashes."
        },
        "status" => %{"type" => "string"},
        "source_feature_request_id" => %{"type" => "string"}
      }
    }

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.MCP.Tool
  alias Hive.Specs

  @impl EMCP.Tool
  def description do
    "Create a Hive spec, optionally linked to a feature request forage item. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, args) do
    attrs =
      args
      |> Map.take(["title", "body", "summary", "status", "source_feature_request_id"])
      |> Map.put_new("status", "draft")

    case Specs.create_spec(attrs, conn.assigns.current_user) do
      {:ok, spec} ->
        Tool.json_response(%{
          spec: spec.id |> Specs.get_spec!() |> SpecTool.spec_json()
        })

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

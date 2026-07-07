defmodule Hive.MCP.Components.Tools.CreateForageItem do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "create_forage_item",
    title: "Create Forage Item",
    read_only_hint: false,
    open_world_hint: true,
    schema: %{
      "type" => "object",
      "required" => ["title", "description"],
      "properties" => %{
        "type" => %{
          "type" => "string",
          "enum" => ["feature_request", "bug_report", "feedback"],
          "description" => "The kind of forage item to create. Defaults to feature_request."
        },
        "title" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "destination" => %{
          "type" => "string",
          "enum" => ["hive_item", "github_issue"],
          "description" => "Optional destination override. Omit this to use the instance default."
        },
        "source_url" => %{
          "type" => "string",
          "description" => "Optional source URL that explains where the request came from."
        },
        "source_label" => %{
          "type" => "string",
          "description" => "Optional label for the source URL."
        }
      }
    }

  alias Hive.Forage.Intake
  alias Hive.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Create a Hive forage item using the instance's configured intake destination. Authenticated user only."
  end

  @impl EMCP.Tool
  def call(conn, args) do
    attrs =
      args
      |> Map.take(["type", "title", "description", "destination", "source_url", "source_label"])
      |> Map.put_new("type", "feature_request")

    case Intake.create(attrs, conn.assigns[:current_user], interface: "mcp") do
      {:ok, result} ->
        Tool.json_response(%{forage_item: result_json(result)})

      {:error, %Ecto.Changeset{} = changeset} ->
        Tool.json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})

      {:error, :unauthorized} ->
        Tool.json_response(%{error: "unauthorized"})

      {:error, :unknown_destination} ->
        Tool.json_response(%{error: "unknown_destination"})

      {:error, :github_repository_not_configured} ->
        Tool.json_response(%{error: "github_repository_not_configured"})

      {:error, :github_repository_not_found} ->
        Tool.json_response(%{error: "github_repository_not_found"})

      {:error, _reason} ->
        Tool.json_response(%{error: "failed"})
    end
  end

  defp result_json(result) do
    %{
      destination: Atom.to_string(result.destination),
      type: Atom.to_string(result.type),
      title: result.target_label,
      hive_url: result.hive_path,
      external_url: result.external_url,
      external_label: result.external_label
    }
  end
end

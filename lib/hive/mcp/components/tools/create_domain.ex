defmodule Hive.MCP.Components.Tools.CreateDomain do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "create_domain",
    title: "Create Domain",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{
        "name" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "visibility" => %{
          "type" => "string",
          "enum" => ["public", "private"],
          "description" => "Domain visibility."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"domain" => Hive.MCP.Components.Tools.Domains.domain_schema()},
        ["domain"]
      )

  alias Hive.Auth
  alias Hive.Domains
  alias Hive.MCP.Components.Tools.Domains, as: DomainTool
  alias Hive.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Create a reusable domain. Organization member only."

  @impl EMCP.Tool
  def call(conn, args) do
    if Auth.member?(conn.assigns[:current_user]) do
      args
      |> Map.take(["name", "description", "visibility"])
      |> Domains.create_domain()
      |> case do
        {:ok, domain} ->
          json_response(%{domain: DomainTool.domain_json(domain)})

        {:error, changeset} ->
          json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
      end
    else
      json_response(%{error: "unauthorized"})
    end
  end
end

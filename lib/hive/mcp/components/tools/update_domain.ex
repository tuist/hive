defmodule Hive.MCP.Components.Tools.UpdateDomain do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "update_domain",
    title: "Update Domain",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "Domain UUID."},
        "name" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "visibility" => %{
          "type" => "string",
          "enum" => ["public", "private"],
          "description" => "Domain visibility."
        }
      }
    }

  alias Hive.Auth
  alias Hive.Domains
  alias Hive.MCP.Components.Tools.Domains, as: DomainTool
  alias Hive.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Update a domain. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"id" => id} = args) do
    user = conn.assigns[:current_user]

    cond do
      not Auth.member?(user) ->
        Tool.json_response(%{error: "unauthorized"})

      true ->
        update_domain(user, id, args)
    end
  end

  defp update_domain(user, id, args) do
    case Domains.fetch_visible_domain(id, user) do
      {:ok, domain} ->
        attrs = Map.take(args, ["name", "description", "visibility"])

        case Domains.update_domain(domain, attrs) do
          {:ok, domain} ->
            Tool.json_response(%{domain: DomainTool.domain_json(domain)})

          {:error, changeset} ->
            Tool.json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
        end

      {:error, :not_found} ->
        Tool.json_response(%{error: "not_found"})
    end
  end
end

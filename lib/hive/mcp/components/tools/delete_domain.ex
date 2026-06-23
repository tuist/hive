defmodule Hive.MCP.Components.Tools.DeleteDomain do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "delete_domain",
    title: "Delete Domain",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "Domain UUID."}
      }
    }

  alias Hive.Auth
  alias Hive.Domains
  alias Hive.MCP.Components.Tools.Domains, as: DomainTool
  alias Hive.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Delete a domain. Organization member only."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]

    cond do
      not Auth.member?(user) ->
        Tool.json_response(%{error: "unauthorized"})

      true ->
        delete_domain(user, id)
    end
  end

  defp delete_domain(user, id) do
    case Domains.fetch_visible_domain(id, user) do
      {:ok, domain} ->
        deleted_domain = DomainTool.domain_json(domain)

        case Domains.delete_domain(domain) do
          {:ok, _domain} ->
            Tool.json_response(%{deleted_domain: deleted_domain})

          {:error, changeset} ->
            Tool.json_response(%{error: "invalid", details: Tool.changeset_errors(changeset)})
        end

      {:error, :not_found} ->
        Tool.json_response(%{error: "not_found"})
    end
  end
end

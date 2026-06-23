defmodule Hive.MCP.Components.Tools.GetDomain do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_domain",
    title: "Get Domain",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "Domain UUID."}
      }
    }

  alias Hive.Domains
  alias Hive.MCP.Components.Tools.Domains, as: DomainTool
  alias Hive.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Fetch one domain with its linked projects and repositories."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    case Domains.fetch_visible_domain(id, conn.assigns[:current_user]) do
      {:ok, domain} -> Tool.json_response(%{domain: DomainTool.domain_json(domain)})
      {:error, :not_found} -> Tool.json_response(%{error: "not_found"})
    end
  end
end

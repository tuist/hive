defmodule Hive.MCP.Components.Tools.ListDomains do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_domains",
    title: "List Domains",
    schema: %{
      "type" => "object",
      "properties" => %{
        "visibility" => %{
          "type" => "string",
          "enum" => ["public", "private"],
          "description" => "Restrict to domains with this visibility."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "domains" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Tools.Domains.domain_schema()
          }
        },
        ["domains"]
      )

  alias Hive.Domains
  alias Hive.MCP.Components.Tools.Domains, as: DomainTool

  @impl EMCP.Tool
  def description, do: "List domains visible to the authenticated caller."

  @impl EMCP.Tool
  def call(conn, args) do
    visibility = args["visibility"]

    domains =
      conn.assigns[:current_user]
      |> Domains.list_visible_domains()
      |> Enum.filter(fn domain ->
        is_nil(visibility) or Atom.to_string(domain.visibility) == visibility
      end)

    json_response(%{domains: Enum.map(domains, &DomainTool.domain_json/1)})
  end
end

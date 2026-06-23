defmodule Hive.MCP.Components.Tools.CreateDomainTest do
  use Hive.MCPToolCase

  alias Hive.Domains
  alias Hive.MCP.Components.Tools.CreateDomain

  test "creates a domain for members" do
    user = mcp_user("create-domain@example.com", :member)
    name = unique_name("CLI")

    response =
      user
      |> mcp_conn()
      |> CreateDomain.call(%{
        "name" => name,
        "description" => "Command line interface.",
        "visibility" => "private"
      })
      |> response_json()

    assert %{"domain" => %{"id" => id, "name" => ^name, "visibility" => "private"}} = response
    assert Domains.get_domain!(id).description == "Command line interface."
  end

  test "rejects collaborators" do
    user = mcp_user("create-domain-collaborator@example.com", :collaborator)

    response =
      user
      |> mcp_conn()
      |> CreateDomain.call(%{"name" => unique_name("CLI")})
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end
end

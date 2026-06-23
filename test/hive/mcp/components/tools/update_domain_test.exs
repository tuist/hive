defmodule Hive.MCP.Components.Tools.UpdateDomainTest do
  use Hive.MCPToolCase

  alias Hive.Domains
  alias Hive.MCP.Components.Tools.UpdateDomain

  test "updates a domain for members" do
    user = mcp_user("update-domain@example.com", :member)
    {:ok, domain} = Domains.create_domain(%{name: unique_name("Cache")})
    new_name = unique_name("Cache Updated")

    response =
      user
      |> mcp_conn()
      |> UpdateDomain.call(%{
        "id" => domain.id,
        "name" => new_name,
        "description" => "Updated description.",
        "visibility" => "private"
      })
      |> response_json()

    assert response["domain"]["name"] == new_name
    assert response["domain"]["visibility"] == "private"
    assert Domains.get_domain!(domain.id).description == "Updated description."
  end

  test "rejects collaborators" do
    user = mcp_user("update-domain-collaborator@example.com", :collaborator)
    {:ok, domain} = Domains.create_domain(%{name: unique_name("Cache")})

    response =
      user
      |> mcp_conn()
      |> UpdateDomain.call(%{"id" => domain.id, "name" => unique_name("Denied")})
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end
end

defmodule Hive.MCP.Components.Tools.DeleteDomainTest do
  use Hive.MCPToolCase

  alias Hive.Domains
  alias Hive.Domains.Domain
  alias Hive.MCP.Components.Tools.DeleteDomain
  alias Hive.Repo

  test "deletes a domain for members" do
    user = mcp_user("delete-domain@example.com", :member)
    {:ok, domain} = Domains.create_domain(%{name: unique_name("Cache")})

    response =
      user
      |> mcp_conn()
      |> DeleteDomain.call(%{"id" => domain.id})
      |> response_json()

    assert response["deleted_domain"]["id"] == domain.id
    refute Repo.get(Domain, domain.id)
  end

  test "rejects collaborators" do
    user = mcp_user("delete-domain-collaborator@example.com", :collaborator)
    {:ok, domain} = Domains.create_domain(%{name: unique_name("Cache")})

    response =
      user
      |> mcp_conn()
      |> DeleteDomain.call(%{"id" => domain.id})
      |> response_json()

    assert response == %{"error" => "unauthorized"}
    assert Domains.get_domain!(domain.id)
  end
end

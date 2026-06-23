defmodule Hive.MCP.Components.Tools.GetDomainTest do
  use Hive.MCPToolCase

  alias Hive.Domains
  alias Hive.MCP.Components.Tools.GetDomain

  test "returns a visible domain" do
    user = mcp_user("get-domain@example.com", :member)

    {:ok, domain} =
      Domains.create_domain(%{name: unique_name("Cache"), description: "Build cache."})

    response =
      user
      |> mcp_conn()
      |> GetDomain.call(%{"id" => domain.id})
      |> response_json()

    assert response["domain"]["id"] == domain.id
    assert response["domain"]["description"] == "Build cache."
    assert response["domain"]["projects"] == []
  end

  test "hides private domains from collaborators" do
    user = mcp_user("get-domain-collaborator@example.com", :collaborator)
    {:ok, domain} = Domains.create_domain(%{name: unique_name("Private"), visibility: "private"})

    response =
      user
      |> mcp_conn()
      |> GetDomain.call(%{"id" => domain.id})
      |> response_json()

    assert response == %{"error" => "not_found"}
  end
end

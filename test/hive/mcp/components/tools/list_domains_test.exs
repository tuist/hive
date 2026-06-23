defmodule Hive.MCP.Components.Tools.ListDomainsTest do
  use Hive.MCPToolCase

  alias Hive.Domains
  alias Hive.MCP.Components.Tools.ListDomains

  test "lists visible domains for the caller" do
    member = mcp_user("member-domains@example.com", :member)
    collaborator = mcp_user("collaborator-domains@example.com", :collaborator)

    {:ok, public_domain} =
      Domains.create_domain(%{name: unique_name("Public"), visibility: "public"})

    {:ok, private_domain} =
      Domains.create_domain(%{name: unique_name("Private"), visibility: "private"})

    collaborator_response =
      collaborator
      |> mcp_conn()
      |> ListDomains.call(%{})
      |> response_json()

    assert Enum.map(collaborator_response["domains"], & &1["id"]) == [public_domain.id]

    member_response =
      member
      |> mcp_conn()
      |> ListDomains.call(%{})
      |> response_json()

    assert member_response["domains"] |> Enum.map(& &1["id"]) |> Enum.sort() ==
             [private_domain.id, public_domain.id] |> Enum.sort()
  end

  test "filters by visibility" do
    user = mcp_user("domain-filter@example.com", :member)

    {:ok, public_domain} =
      Domains.create_domain(%{name: unique_name("Public"), visibility: "public"})

    {:ok, _private_domain} =
      Domains.create_domain(%{name: unique_name("Private"), visibility: "private"})

    response =
      user
      |> mcp_conn()
      |> ListDomains.call(%{"visibility" => "public"})
      |> response_json()

    assert Enum.map(response["domains"], & &1["id"]) == [public_domain.id]
  end
end

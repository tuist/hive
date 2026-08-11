defmodule Hive.MCP.Components.Tools.CreatePostmortemTest do
  use Hive.MCPToolCase

  alias Hive.Domains
  alias Hive.MCP.Components.Tools.CreatePostmortem

  test "publishes a postmortem with domains for members" do
    user = mcp_user()
    {:ok, domain} = Domains.create_domain(%{name: unique_name("Registry")})

    response =
      CreatePostmortem.call(mcp_conn(user), %{
        "body" => "# Registry incident\n\nPackage delivery was delayed.",
        "visibility" => "public",
        "domain_ids" => [domain.id]
      })
      |> response_json()

    assert response["postmortem"]["title"] == "Registry incident"
    assert response["postmortem"]["author"]["email"] == user.email
    assert [%{"id" => domain_id}] = response["postmortem"]["domains"]
    assert domain_id == domain.id
  end

  test "rejects collaborators" do
    user = mcp_user("postmortem-collaborator@example.com", :collaborator)

    response =
      CreatePostmortem.call(mcp_conn(user), %{
        "body" => "# Registry incident\n\nPackage delivery was delayed."
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end
end

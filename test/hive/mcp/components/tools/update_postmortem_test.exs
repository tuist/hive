defmodule Hive.MCP.Components.Tools.UpdatePostmortemTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.UpdatePostmortem
  alias Hive.Postmortems

  test "updates postmortems referenced by shared path" do
    user = mcp_user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        user
      )

    response =
      UpdatePostmortem.call(mcp_conn(user), %{
        "id" => "/postmortems/#{postmortem.number}",
        "body" => "# Registry recovery\n\nPackage delivery has recovered.",
        "visibility" => "private"
      })
      |> response_json()

    assert response["postmortem"]["title"] == "Registry recovery"
    assert response["postmortem"]["visibility"] == "private"
  end

  test "rejects collaborator updates" do
    member = mcp_user("postmortem-member@example.com", :member)
    collaborator = mcp_user("postmortem-editor@example.com", :collaborator)

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        member
      )

    response =
      UpdatePostmortem.call(mcp_conn(collaborator), %{
        "id" => postmortem.id,
        "body" => "# Changed incident\n\nThis write is not allowed."
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end
end

defmodule Hive.MCP.Components.Tools.CreatePostmortemActionItemTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.CreatePostmortemActionItem
  alias Hive.Postmortems

  test "creates an action item for members" do
    user = mcp_user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        user
      )

    response =
      CreatePostmortemActionItem.call(mcp_conn(user), %{
        "postmortem_id" => "/postmortems/#{postmortem.number}",
        "title" => "Add a registry latency alert",
        "description" => "Page when latency is high."
      })
      |> response_json()

    assert response["action_item"]["postmortem_id"] == postmortem.id
    assert response["action_item"]["title"] == "Add a registry latency alert"
    assert response["action_item"]["description"] == "Page when latency is high."
  end

  test "rejects collaborators" do
    member = mcp_user("action-item-member@example.com", :member)
    collaborator = mcp_user("action-item-collaborator@example.com", :collaborator)

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        member
      )

    response =
      CreatePostmortemActionItem.call(mcp_conn(collaborator), %{
        "postmortem_id" => postmortem.id,
        "title" => "Add a registry latency alert"
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end
end

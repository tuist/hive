defmodule Hive.MCP.Components.Tools.GetPostmortemActionItemTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.GetPostmortemActionItem
  alias Hive.Postmortems

  test "fetches an action item from a visible postmortem" do
    user = mcp_user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        user
      )

    {:ok, action_item} =
      Postmortems.create_action_item(
        postmortem,
        %{"title" => "Add an alert", "description" => "Page when latency is high."},
        user
      )

    response =
      GetPostmortemActionItem.call(mcp_conn(nil), %{"action_item_id" => action_item.id})
      |> response_json()

    assert response["action_item"]["id"] == action_item.id
    assert response["action_item"]["completed"] == false
  end

  test "hides action items from private postmortems" do
    user = mcp_user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Private incident\n\nPrivate incident details.", "visibility" => "private"},
        user
      )

    {:ok, action_item} =
      Postmortems.create_action_item(postmortem, %{"title" => "Add an alert"}, user)

    response =
      GetPostmortemActionItem.call(mcp_conn(nil), %{"action_item_id" => action_item.id})
      |> response_json()

    assert response == %{"error" => "not_found"}
  end
end

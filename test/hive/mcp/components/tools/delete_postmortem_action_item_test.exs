defmodule Hive.MCP.Components.Tools.DeletePostmortemActionItemTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.DeletePostmortemActionItem
  alias Hive.Postmortems
  alias Hive.Postmortems.ActionItem
  alias Hive.Repo

  test "deletes an action item for members" do
    user = mcp_user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        user
      )

    {:ok, action_item} =
      Postmortems.create_action_item(postmortem, %{"title" => "Add an alert"}, user)

    response =
      DeletePostmortemActionItem.call(mcp_conn(user), %{"action_item_id" => action_item.id})
      |> response_json()

    assert response["deleted_action_item"]["id"] == action_item.id
    refute Repo.get(ActionItem, action_item.id)
  end

  test "rejects collaborators" do
    member = mcp_user("action-item-delete-member@example.com", :member)
    collaborator = mcp_user("action-item-delete-collaborator@example.com", :collaborator)

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        member
      )

    {:ok, action_item} =
      Postmortems.create_action_item(postmortem, %{"title" => "Add an alert"}, member)

    response =
      DeletePostmortemActionItem.call(mcp_conn(collaborator), %{
        "action_item_id" => action_item.id
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
    assert Repo.get(ActionItem, action_item.id)
  end
end

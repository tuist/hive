defmodule Hive.MCP.Components.Tools.UpdatePostmortemActionItemTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.UpdatePostmortemActionItem
  alias Hive.Postmortems

  test "updates action-item text and completion state" do
    user = mcp_user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        user
      )

    {:ok, action_item} =
      Postmortems.create_action_item(postmortem, %{"title" => "Add an alert"}, user)

    completed_response =
      UpdatePostmortemActionItem.call(mcp_conn(user), %{
        "action_item_id" => action_item.id,
        "title" => "Add a registry latency alert",
        "description" => "Page when latency is high.",
        "priority" => "immediate",
        "completed" => true
      })
      |> response_json()

    assert completed_response["action_item"]["title"] == "Add a registry latency alert"
    assert completed_response["action_item"]["priority"] == "immediate"
    assert completed_response["action_item"]["completed"] == true
    assert is_binary(completed_response["action_item"]["completed_at"])

    reopened_response =
      UpdatePostmortemActionItem.call(mcp_conn(user), %{
        "action_item_id" => action_item.id,
        "completed" => false
      })
      |> response_json()

    assert reopened_response["action_item"]["completed"] == false
    assert reopened_response["action_item"]["completed_at"] == nil
  end

  test "rejects collaborator updates" do
    member = mcp_user("action-item-update-member@example.com", :member)
    collaborator = mcp_user("action-item-update-collaborator@example.com", :collaborator)

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        member
      )

    {:ok, action_item} =
      Postmortems.create_action_item(postmortem, %{"title" => "Add an alert"}, member)

    response =
      UpdatePostmortemActionItem.call(mcp_conn(collaborator), %{
        "action_item_id" => action_item.id,
        "completed" => true
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end
end

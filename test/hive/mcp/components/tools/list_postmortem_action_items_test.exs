defmodule Hive.MCP.Components.Tools.ListPostmortemActionItemsTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.ListPostmortemActionItems
  alias Hive.Postmortems

  test "lists action items for a visible postmortem" do
    user = mcp_user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        user
      )

    {:ok, first} =
      Postmortems.create_action_item(postmortem, %{"title" => "Add an alert"}, user)

    {:ok, second} =
      Postmortems.create_action_item(postmortem, %{"title" => "Write the runbook"}, user)

    response =
      ListPostmortemActionItems.call(mcp_conn(nil), %{
        "postmortem_id" => to_string(postmortem.number)
      })
      |> response_json()

    assert Enum.map(response["action_items"], & &1["id"]) == [first.id, second.id]
  end
end

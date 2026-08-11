defmodule Hive.MCP.Components.Tools.GetPostmortemTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.GetPostmortem
  alias Hive.Postmortems

  test "fetches a postmortem by shared address with its action items" do
    user = mcp_user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        user
      )

    {:ok, action_item} =
      Postmortems.create_action_item(
        postmortem,
        %{"title" => "Add a registry latency alert"},
        user
      )

    response =
      GetPostmortem.call(mcp_conn(user), %{
        "id" => "https://hive.test/postmortems/#{postmortem.number}"
      })
      |> response_json()

    assert response["postmortem"]["id"] == postmortem.id
    assert response["postmortem"]["title"] == "Registry incident"
    assert [%{"id" => action_item_id}] = response["postmortem"]["action_items"]
    assert action_item_id == action_item.id
  end

  test "hides private postmortems from anonymous callers" do
    user = mcp_user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Private incident\n\nPrivate incident details.", "visibility" => "private"},
        user
      )

    response = GetPostmortem.call(mcp_conn(nil), %{"id" => postmortem.id}) |> response_json()

    assert response == %{"error" => "not_found"}
  end
end

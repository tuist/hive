defmodule Hive.MCP.Components.Tools.DeletePostmortemTest do
  use Hive.MCPToolCase

  alias Hive.Audit.Activity
  alias Hive.MCP.Components.Tools.DeletePostmortem
  alias Hive.Postmortems
  alias Hive.Postmortems.ActionItem
  alias Hive.Postmortems.Postmortem
  alias Hive.Repo

  test "deletes a postmortem and its action items for members" do
    user = mcp_user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        user
      )

    {:ok, action_item} =
      Postmortems.create_action_item(postmortem, %{"title" => "Add an alert"}, user)

    response =
      DeletePostmortem.call(mcp_conn(user), %{"id" => to_string(postmortem.number)})
      |> response_json()

    assert response["deleted_postmortem"]["id"] == postmortem.id
    refute Repo.get(Postmortem, postmortem.id)
    refute Repo.get(ActionItem, action_item.id)

    assert Repo.get_by!(Activity, action: "postmortem.deleted", target_id: postmortem.id)
  end

  test "rejects collaborators" do
    member = mcp_user("postmortem-delete-member@example.com", :member)
    collaborator = mcp_user("postmortem-delete-collaborator@example.com", :collaborator)

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry incident\n\nPackage delivery was delayed."},
        member
      )

    response =
      DeletePostmortem.call(mcp_conn(collaborator), %{"id" => postmortem.id})
      |> response_json()

    assert response == %{"error" => "unauthorized"}
    assert Repo.get(Postmortem, postmortem.id)
  end
end

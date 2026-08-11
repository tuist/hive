defmodule Hive.MCP.Components.Tools.ListPostmortemsTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.ListPostmortems
  alias Hive.Postmortems

  test "lists only postmortems visible to the caller" do
    user = mcp_user()

    {:ok, public_postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Public incident\n\nDetails for everyone.", "visibility" => "public"},
        user
      )

    {:ok, private_postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Private incident\n\nDetails for members.", "visibility" => "private"},
        user
      )

    anonymous_response = ListPostmortems.call(mcp_conn(nil), %{}) |> response_json()
    member_response = ListPostmortems.call(mcp_conn(user), %{}) |> response_json()

    assert Enum.map(anonymous_response["postmortems"], & &1["id"]) == [public_postmortem.id]

    assert MapSet.new(member_response["postmortems"], & &1["id"]) ==
             MapSet.new([public_postmortem.id, private_postmortem.id])
  end
end

defmodule Hive.MCP.Components.Tools.DeleteSpecCommentTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.DeleteSpecComment
  alias Hive.Specs

  test "deletes comments for their author" do
    user = mcp_user()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
    {:ok, comment} = Specs.add_comment(spec, %{"body" => "Initial note."}, user)

    response =
      DeleteSpecComment.call(mcp_conn(user), %{"comment_id" => comment.id})
      |> response_json()

    assert response["spec"]["comments"] == []
  end

  test "rejects comment deletes from other users" do
    author = mcp_user("author@example.com")
    other_user = mcp_user("other@example.com")
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)
    {:ok, comment} = Specs.add_comment(spec, %{"body" => "Initial note."}, author)

    response =
      DeleteSpecComment.call(mcp_conn(other_user), %{"comment_id" => comment.id})
      |> response_json()

    assert response["error"] == "unauthorized"

    spec = Specs.get_spec!(spec.id)
    assert Enum.map(spec.comments, & &1.body) == ["Initial note."]
  end
end

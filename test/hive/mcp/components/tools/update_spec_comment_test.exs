defmodule Hive.MCP.Components.Tools.UpdateSpecCommentTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.UpdateSpecComment
  alias Hive.Specs

  test "updates comments for their author" do
    user = mcp_user()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
    {:ok, comment} = Specs.add_comment(spec, %{"body" => "Initial note."}, user)

    response =
      UpdateSpecComment.call(mcp_conn(user), %{
        "comment_id" => comment.id,
        "body" => "Updated note."
      })
      |> response_json()

    assert [%{"id" => comment_id, "body" => "Updated note.", "author" => "alice@example.com"}] =
             response["spec"]["comments"]

    assert comment_id == comment.id
  end

  test "rejects comment updates from other users" do
    author = mcp_user("author@example.com")
    other_user = mcp_user("other@example.com")
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)
    {:ok, comment} = Specs.add_comment(spec, %{"body" => "Initial note."}, author)

    response =
      UpdateSpecComment.call(mcp_conn(other_user), %{
        "comment_id" => comment.id,
        "body" => "Hijacked."
      })
      |> response_json()

    assert response["error"] == "unauthorized"

    spec = Specs.get_spec!(spec.id)
    assert Enum.map(spec.comments, & &1.body) == ["Initial note."]
  end
end

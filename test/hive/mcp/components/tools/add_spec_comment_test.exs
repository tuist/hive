defmodule Hive.MCP.Components.Tools.AddSpecCommentTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.AddSpecComment
  alias Hive.Specs

  test "adds authenticated comments to a spec referenced by shared URL" do
    user = mcp_user()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    response =
      AddSpecComment.call(mcp_conn(user), %{
        "spec_id" => "https://hive.test/specs/#{spec.number}",
        "body" => "This looks ready."
      })
      |> response_json()

    assert [%{"body" => "This looks ready.", "author" => "alice@example.com"}] =
             response["spec"]["comments"]
  end

  test "requires authentication to comment on a public spec" do
    user = mcp_user()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    response =
      AddSpecComment.call(mcp_conn(nil), %{
        "spec_id" => "https://hive.test/specs/#{spec.number}",
        "body" => "Anonymous comment."
      })
      |> response_json()

    assert response["error"] == "unauthorized"
  end
end

defmodule Hive.MCP.Components.Tools.ListSpecCommentsTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.ListSpecComments
  alias Hive.Specs

  test "lists comments for a visible spec referenced by shared URL" do
    user = mcp_user()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
    {:ok, _comment} = Specs.add_comment(spec, %{"body" => "First note."}, user)
    {:ok, _comment} = Specs.add_comment(spec, %{"body" => "Second note."}, user)

    response =
      ListSpecComments.call(mcp_conn(user), %{
        "spec_id" => "https://hive.test/specs/#{spec.number}"
      })
      |> response_json()

    assert response["spec"]["id"] == spec.id

    assert [
             %{"body" => "First note.", "author" => "alice@example.com"},
             %{"body" => "Second note.", "author" => "alice@example.com"}
           ] = response["comments"]
  end

  test "hides comments for specs the caller cannot see" do
    user = mcp_user()

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Private",
          "body" => "Initial proposal.",
          "visibility_override" => "private"
        },
        user
      )

    {:ok, _comment} = Specs.add_comment(spec, %{"body" => "Private note."}, user)

    response =
      ListSpecComments.call(mcp_conn(nil), %{"spec_id" => spec.id})
      |> response_json()

    assert response["error"] == "not_found"
  end
end

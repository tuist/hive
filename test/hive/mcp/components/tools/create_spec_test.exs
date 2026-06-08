defmodule Hive.MCP.Components.Tools.CreateSpecTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.CreateSpec

  test "creates specs with default status and visibility" do
    user = mcp_user()

    response =
      CreateSpec.call(mcp_conn(user), %{
        "title" => "GitHub sign-in",
        "body" => "Add GitHub sign-in for requesters.",
        "summary" => "Let requesters authenticate with GitHub."
      })
      |> response_json()

    assert %{"spec" => %{"number" => number, "revision" => 1}} = response
    assert is_integer(number)
    assert response["spec"]["summary"] == "Let requesters authenticate with GitHub."
    assert response["spec"]["status"] == "draft"
    assert response["spec"]["visibility"] == "public"

    assert [%{"revision" => 1, "title" => "GitHub sign-in"}] =
             response["spec"]["revisions"]
  end
end

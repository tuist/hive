defmodule Hive.MCP.Components.Tools.ListSpecsTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.ListSpecs
  alias Hive.Specs

  test "lists visible specs" do
    user = mcp_user()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    response = ListSpecs.call(mcp_conn(user), %{}) |> response_json()

    assert [%{"id" => id}] = response["specs"]
    assert id == spec.id
  end
end

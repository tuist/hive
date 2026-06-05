defmodule Hive.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Hive.MCP.Server

  test "returns a server with the Hive tools" do
    server = Server.server()

    assert Map.keys(server.tools) == ["whoami"]
  end

  test "every tool exposes review hints" do
    server = Server.server()

    for {name, module} <- server.tools do
      annotations = module.annotations()

      assert is_binary(annotations[:title]) and annotations[:title] != "",
             "tool #{name} is missing a title"

      assert is_boolean(annotations[:readOnlyHint])
      assert is_boolean(annotations[:openWorldHint])
      assert is_boolean(annotations[:destructiveHint])
    end
  end
end

defmodule Hive.MCP.Server do
  @moduledoc false

  use EMCP.Server,
    name: "hive",
    version: "0.1.0",
    tools: [
      Hive.MCP.Components.Tools.Whoami
    ]
end

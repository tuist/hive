defmodule Hive.MCP.Server do
  @moduledoc false

  use EMCP.Server,
    name: "hive",
    version: "0.1.0",
    tools: [
      Hive.MCP.Components.Tools.Whoami,
      Hive.MCP.Components.Tools.ListSpecs,
      Hive.MCP.Components.Tools.GetSpec,
      Hive.MCP.Components.Tools.CreateSpec,
      Hive.MCP.Components.Tools.UpdateSpec,
      Hive.MCP.Components.Tools.AddSpecComment,
      Hive.MCP.Components.Tools.ListAuditActivities,
      Hive.MCP.Components.Tools.GetAuditActivity
    ],
    prompts: [
      Hive.MCP.Components.Prompts.WriteSpec
    ]
end

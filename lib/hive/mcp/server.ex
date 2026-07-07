defmodule Hive.MCP.Server do
  @moduledoc false

  use EMCP.Server,
    name: "hive",
    version: "0.1.0",
    tools: [
      Hive.MCP.Components.Tools.Whoami,
      Hive.MCP.Components.Tools.ListProjects,
      Hive.MCP.Components.Tools.GetProject,
      Hive.MCP.Components.Tools.CreateProject,
      Hive.MCP.Components.Tools.UpdateProject,
      Hive.MCP.Components.Tools.DeleteProject,
      Hive.MCP.Components.Tools.ListDomains,
      Hive.MCP.Components.Tools.GetDomain,
      Hive.MCP.Components.Tools.CreateDomain,
      Hive.MCP.Components.Tools.UpdateDomain,
      Hive.MCP.Components.Tools.DeleteDomain,
      Hive.MCP.Components.Tools.LinkProjectDomain,
      Hive.MCP.Components.Tools.UnlinkProjectDomain,
      Hive.MCP.Components.Tools.LinkProjectRepository,
      Hive.MCP.Components.Tools.UnlinkProjectRepository,
      Hive.MCP.Components.Tools.CreateProjectWebhook,
      Hive.MCP.Components.Tools.DeleteProjectWebhook,
      Hive.MCP.Components.Tools.CreateForageItem,
      Hive.MCP.Components.Tools.ListSpecs,
      Hive.MCP.Components.Tools.GetSpec,
      Hive.MCP.Components.Tools.CreateSpec,
      Hive.MCP.Components.Tools.UpdateSpec,
      Hive.MCP.Components.Tools.RequestSpecReview,
      Hive.MCP.Components.Tools.ListSpecComments,
      Hive.MCP.Components.Tools.AddSpecComment,
      Hive.MCP.Components.Tools.UpdateSpecComment,
      Hive.MCP.Components.Tools.DeleteSpecComment,
      Hive.MCP.Components.Tools.ListAuditActivities,
      Hive.MCP.Components.Tools.GetAuditActivity,
      Hive.MCP.Components.Tools.ListDrops,
      Hive.MCP.Components.Tools.GetDrop
    ],
    prompts: [
      Hive.MCP.Components.Prompts.WriteSpec
    ]
end

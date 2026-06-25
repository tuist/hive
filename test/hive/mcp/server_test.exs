defmodule Hive.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Hive.MCP.Server

  test "returns a server with the Hive tools" do
    server = Server.server()

    assert server.tools |> Map.keys() |> Enum.sort() == [
             "add_spec_comment",
             "create_domain",
             "create_project",
             "create_project_webhook",
             "create_spec",
             "delete_domain",
             "delete_project",
             "delete_project_webhook",
             "delete_spec_comment",
             "get_audit_activity",
             "get_domain",
             "get_drop",
             "get_project",
             "get_spec",
             "link_project_domain",
             "link_project_repository",
             "list_audit_activities",
             "list_domains",
             "list_drops",
             "list_projects",
             "list_spec_comments",
             "list_specs",
             "request_spec_review",
             "unlink_project_domain",
             "unlink_project_repository",
             "update_domain",
             "update_project",
             "update_spec",
             "update_spec_comment",
             "whoami"
           ]
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

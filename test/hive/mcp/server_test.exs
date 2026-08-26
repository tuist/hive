defmodule Hive.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Hive.MCP.Server
  alias Hive.MCP.Tool

  test "returns a server with the Hive tools" do
    server = Server.server()

    assert server.tools |> Map.keys() |> Enum.sort() == [
             "add_spec_comment",
             "create_domain",
             "create_forage_item",
             "create_postmortem",
             "create_postmortem_action_item",
             "create_project",
             "create_project_webhook",
             "create_spec",
             "delete_domain",
             "delete_postmortem",
             "delete_postmortem_action_item",
             "delete_project",
             "delete_project_webhook",
             "delete_spec",
             "delete_spec_comment",
             "get_audit_activity",
             "get_domain",
             "get_drop",
             "get_drop_digest",
             "get_flight",
             "get_inference_usage",
             "get_postmortem",
             "get_postmortem_action_item",
             "get_project",
             "get_spec",
             "link_project_domain",
             "link_project_repository",
             "list_audit_activities",
             "list_domains",
             "list_drop_digests",
             "list_drops",
             "list_flights",
             "list_inference_profiles",
             "list_inference_providers",
             "list_inference_tokens",
             "list_notification_preferences",
             "list_postmortem_action_items",
             "list_postmortems",
             "list_projects",
             "list_spec_comments",
             "list_specs",
             "request_spec_review",
             "set_notification_preference",
             "start_forage_item_flight",
             "start_grafana_alert_flight",
             "unlink_project_domain",
             "unlink_project_repository",
             "update_domain",
             "update_postmortem",
             "update_postmortem_action_item",
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

  test "every tool advertises an object output schema" do
    server = Server.server()

    for {name, module} <- server.tools do
      descriptor = Tool.descriptor(module)

      assert descriptor["outputSchema"]["type"] == "object",
             "tool #{name} is missing an object output schema"
    end
  end
end

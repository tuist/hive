defmodule Hive.MCP.Components.Tools.ListErrorEventsTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Errors
  alias Hive.MCP.Components.Tools.ListErrorEvents

  setup :verify_on_exit!

  test "returns clickhouse_disabled when ClickHouse is off" do
    stub(Hive.Errors.Availability, :enabled?, fn -> false end)
    user = mcp_user("member@example.com", :member)

    response = ListErrorEvents.call(mcp_conn(user), %{"issue_id" => "abc"})
    assert response_json(response) == %{"error" => "clickhouse_disabled"}
  end

  test "rejects non-members" do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    outsider = mcp_user("guest@example.com", :collaborator)

    response = ListErrorEvents.call(mcp_conn(outsider), %{"issue_id" => "abc"})
    assert response_json(response) == %{"error" => "forbidden"}
  end

  test "returns events for members when ClickHouse is enabled" do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)

    stub(Errors, :list_events_for_issue, fn _id, _opts ->
      [
        %{
          event_id: "abc",
          timestamp: ~U[2026-09-03 12:00:00.000000Z],
          level: "error",
          environment: "production",
          release: "1.0.0",
          exception_type: "Boom",
          exception_value: "!",
          top_frame_function: "explode/0",
          top_frame_filename: "lib/x.ex",
          payload: %{}
        }
      ]
    end)

    user = mcp_user("member@example.com", :member)

    response = ListErrorEvents.call(mcp_conn(user), %{"issue_id" => "abc"})
    assert %{"events" => [%{"exception_type" => "Boom"}]} = response_json(response)
  end
end

defmodule Hive.MCP.Components.Tools.GetErrorEventTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Errors
  alias Hive.MCP.Components.Tools.GetErrorEvent

  setup :verify_on_exit!

  test "returns clickhouse_disabled when ClickHouse is off" do
    stub(Hive.Errors.Availability, :enabled?, fn -> false end)
    user = mcp_user("member@example.com", :member)

    response =
      GetErrorEvent.call(mcp_conn(user), %{"issue_id" => "abc", "event_id" => "xyz"})

    assert response_json(response) == %{"error" => "clickhouse_disabled"}
  end

  test "rejects non-members" do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    outsider = mcp_user("guest@example.com", :collaborator)

    response =
      GetErrorEvent.call(mcp_conn(outsider), %{"issue_id" => "abc", "event_id" => "xyz"})

    assert response_json(response) == %{"error" => "forbidden"}
  end

  test "returns not_found when the event does not exist" do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    stub(Errors, :fetch_event, fn _issue, _event -> nil end)
    user = mcp_user("member@example.com", :member)

    response = GetErrorEvent.call(mcp_conn(user), %{"issue_id" => "abc", "event_id" => "xyz"})
    assert response_json(response) == %{"error" => "not_found"}
  end

  test "returns the event when found" do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)

    stub(Errors, :fetch_event, fn _issue, _event ->
      %{
        event_id: "abcd-1234",
        timestamp: ~U[2026-09-03 12:00:00.000000Z],
        level: "error",
        environment: "production",
        release: "1.0.0",
        exception_type: "Boom",
        exception_value: "boom",
        top_frame_function: "explode/0",
        top_frame_filename: "lib/x.ex",
        payload: %{"platform" => "elixir"}
      }
    end)

    user = mcp_user("member@example.com", :member)

    response = GetErrorEvent.call(mcp_conn(user), %{"issue_id" => "abc", "event_id" => "xyz"})

    assert %{"event" => %{"exception_type" => "Boom", "payload" => %{"platform" => "elixir"}}} =
             response_json(response)
  end
end

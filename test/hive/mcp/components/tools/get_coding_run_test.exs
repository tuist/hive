defmodule Hive.MCP.Components.Tools.GetCodingRunTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Forage.CodingRun
  alias Hive.Forage.CodingRuns
  alias Hive.MCP.Components.Tools.GetCodingRun

  test "returns a completed coding run to an organization member" do
    user = mcp_user("get-coding-run@example.com", :member)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    run = %CodingRun{
      id: Ecto.UUID.generate(),
      forage_item_id: "grafana_alert:alert-id",
      status: :succeeded,
      runner: "microsandbox",
      repository_full_name: "tuist/hive",
      input: %{},
      result: %{
        "type" => "pull_request",
        "url" => "https://github.example/tuist/hive/pull/42"
      },
      inserted_at: now,
      updated_at: now,
      started_at: now,
      completed_at: now
    }

    expect(CodingRuns, :get_for_user, fn id, caller ->
      assert id == run.id
      assert caller.id == user.id
      run
    end)

    response =
      user
      |> mcp_conn()
      |> GetCodingRun.call(%{"id" => run.id})
      |> response_json()

    assert response["coding_run"]["status"] == "succeeded"
    assert response["coding_run"]["result"]["type"] == "pull_request"
    assert response["coding_run"]["completed_at"] == DateTime.to_iso8601(now)
  end

  test "hides missing or unauthorized runs" do
    user = mcp_user("missing-coding-run@example.com", :collaborator)
    expect(CodingRuns, :get_for_user, fn _id, ^user -> nil end)

    response =
      user
      |> mcp_conn()
      |> GetCodingRun.call(%{"id" => Ecto.UUID.generate()})
      |> response_json()

    assert response == %{"error" => "not_found"}
  end
end

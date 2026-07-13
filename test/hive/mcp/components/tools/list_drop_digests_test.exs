defmodule Hive.MCP.Components.Tools.ListDropDigestsTest do
  use Hive.MCPToolCase

  alias Hive.Drops.WeeklyDigest
  alias Hive.MCP.Components.Tools.ListDropDigests

  test "lists published weekly editions newest first" do
    older = insert_digest!(~D[2026-06-29], "Older edition")
    latest = insert_digest!(~D[2026-07-06], "Latest edition")

    response = ListDropDigests.call(mcp_conn(mcp_user()), %{}) |> response_json()

    assert [latest_json, older_json] = response["digests"]
    assert latest_json["id"] == latest.id
    assert latest_json["title"] == "Latest edition"
    assert latest_json["week_start"] == "2026-07-06"
    assert latest_json["week_end"] == "2026-07-10"
    assert latest_json["drop_count"] == 1
    assert latest_json["hive_url"] == "/drops/digest/2026-07-06"
    assert older_json["id"] == older.id
  end

  test "respects the requested limit" do
    insert_digest!(~D[2026-06-29], "Older edition")
    insert_digest!(~D[2026-07-06], "Latest edition")

    response =
      ListDropDigests.call(mcp_conn(mcp_user()), %{"limit" => 1})
      |> response_json()

    assert [%{"title" => "Latest edition"}] = response["digests"]
  end

  defp insert_digest!(week_start, title) do
    %WeeklyDigest{}
    |> WeeklyDigest.changeset(%{
      week_start: week_start,
      week_end: Date.add(week_start, 4),
      status: :published,
      title: title,
      summary: "Summary",
      body: "Narrated body",
      drop_ids: [Ecto.UUID.generate()],
      published_at: DateTime.new!(Date.add(week_start, 4), ~T[17:00:00], "Etc/UTC")
    })
    |> Hive.Repo.insert!()
  end
end

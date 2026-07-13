defmodule Hive.MCP.Components.Tools.GetDropDigestTest do
  use Hive.MCPToolCase

  alias Hive.Drops.WeeklyDigest
  alias Hive.MCP.Components.Tools.GetDropDigest

  test "fetches an edition by week start date" do
    digest = insert_digest!()

    response =
      GetDropDigest.call(mcp_conn(mcp_user()), %{"week" => "2026-07-06"})
      |> response_json()

    assert response["digest"]["id"] == digest.id
    assert response["digest"]["title"] == "The connected week"
    assert response["digest"]["body"] == "A full narrated body."
  end

  test "accepts latest and shared digest URLs" do
    digest = insert_digest!()

    latest =
      GetDropDigest.call(mcp_conn(mcp_user()), %{"week" => "latest"})
      |> response_json()

    shared =
      GetDropDigest.call(mcp_conn(mcp_user()), %{
        "week" => "https://hive.test/drops/digest/2026-07-06"
      })
      |> response_json()

    assert latest["digest"]["id"] == digest.id
    assert shared["digest"]["id"] == digest.id
  end

  test "returns not_found for a missing edition" do
    response =
      GetDropDigest.call(mcp_conn(mcp_user()), %{"week" => "2025-01-06"})
      |> response_json()

    assert response["error"] == "not_found"
  end

  defp insert_digest! do
    %WeeklyDigest{}
    |> WeeklyDigest.changeset(%{
      week_start: ~D[2026-07-06],
      week_end: ~D[2026-07-10],
      status: :published,
      title: "The connected week",
      summary: "A short summary.",
      body: "A full narrated body.",
      drop_ids: [Ecto.UUID.generate()],
      published_at: ~U[2026-07-10 17:00:00Z]
    })
    |> Hive.Repo.insert!()
  end
end

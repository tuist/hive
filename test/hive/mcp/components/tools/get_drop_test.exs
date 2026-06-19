defmodule Hive.MCP.Components.Tools.GetDropTest do
  use Hive.MCPToolCase

  alias Hive.Drops
  alias Hive.MCP.Components.Tools.GetDrop
  alias Hive.Meadows

  defp insert_drop!(meadow, attrs) do
    {:ok, drop} = Drops.upsert_drop(attrs)
    Drops.replace_drop_meadows(drop, [meadow.id])
    drop
  end

  test "returns the drop when visible to the user" do
    user = mcp_user()
    {:ok, meadow} = Meadows.create_meadow(%{name: "Hive", visibility: "public"})

    drop =
      insert_drop!(meadow, %{
        source_type: :rss,
        external_id: "ext-1",
        title: "Changelog v1",
        body: "Body",
        url: "https://example.com/changelog/1"
      })

    response = GetDrop.call(mcp_conn(user), %{"id" => drop.id}) |> response_json()

    assert response["drop"]["id"] == drop.id
    assert response["drop"]["title"] == "Changelog v1"
  end

  test "returns not_found when the drop is linked only to a private meadow the user cannot see" do
    user = mcp_user("outsider@external.example")
    {:ok, user} = user |> Ecto.Changeset.change(role: :collaborator) |> Hive.Repo.update()

    {:ok, meadow} = Meadows.create_meadow(%{name: "Hive", visibility: "private"})

    drop =
      insert_drop!(meadow, %{
        source_type: :rss,
        external_id: "ext-1",
        title: "Hidden",
        url: "https://example.com/hidden"
      })

    response = GetDrop.call(mcp_conn(user), %{"id" => drop.id}) |> response_json()

    assert response["error"] == "not_found"
  end
end

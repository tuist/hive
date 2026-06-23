defmodule Hive.MCP.Components.Tools.ListDropsTest do
  use Hive.MCPToolCase

  alias Hive.Drops
  alias Hive.MCP.Components.Tools.ListDrops
  alias Hive.Domains
  alias Hive.Projects

  defp create_domain!(attrs) do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    attrs = Map.put_new(attrs, :project_id, project.id)
    {:ok, domain} = Domains.create_domain(attrs)
    domain
  end

  defp insert_drop!(domain, attrs) do
    {:ok, drop} = Drops.upsert_drop(attrs)
    Drops.replace_drop_domains(drop, [domain.id])
    drop
  end

  test "lists drops the user can read, projected as JSON" do
    user = mcp_user()
    domain = create_domain!(%{name: "Hive", visibility: "public"})

    insert_drop!(domain, %{
      source_type: :rss,
      external_id: "ext-1",
      title: "Changelog v1",
      body: "Initial body",
      url: "https://example.com/changelog/1",
      published_at: ~U[2026-06-18 12:00:00Z]
    })

    response = ListDrops.call(mcp_conn(user), %{}) |> response_json()

    assert [drop_json] = response["drops"]
    assert drop_json["title"] == "Changelog v1"
    assert [%{"name" => "Hive"}] = drop_json["domains"]
    assert drop_json["source_type"] == "rss"
    assert response["meta"]["total_entries"] == 1
  end

  test "filters by source_type" do
    user = mcp_user()
    domain = create_domain!(%{name: "Hive", visibility: "public"})

    insert_drop!(domain, %{
      source_type: :rss,
      external_id: "rss-1",
      title: "RSS drop",
      url: "https://example.com/rss/1"
    })

    insert_drop!(domain, %{
      source_type: :github_release,
      external_id: "gh-1",
      title: "GH release",
      url: "https://github.com/example/repo/releases/tag/v1"
    })

    response =
      ListDrops.call(mcp_conn(user), %{"source_type" => "github_release"})
      |> response_json()

    assert [%{"title" => "GH release"}] = response["drops"]
  end
end

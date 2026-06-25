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

  test "filters by project_id" do
    user = mcp_user()
    project_domain = create_domain!(%{name: "Project drops", visibility: "public"})
    other_domain = create_domain!(%{name: "Other drops", visibility: "public"})

    insert_drop!(project_domain, %{
      source_type: :rss,
      external_id: "project-rss-1",
      title: "Project changelog",
      url: "https://example.com/project/changelog"
    })

    insert_drop!(other_domain, %{
      source_type: :rss,
      external_id: "other-rss-1",
      title: "Other changelog",
      url: "https://example.com/other/changelog"
    })

    response =
      ListDrops.call(mcp_conn(user), %{"project_id" => project_id(project_domain)})
      |> response_json()

    assert [%{"title" => "Project changelog"}] = response["drops"]
  end

  test "filters by query" do
    user = mcp_user()
    domain = create_domain!(%{name: "Hive", visibility: "public"})

    insert_drop!(domain, %{
      source_type: :rss,
      external_id: "search-rss-1",
      title: "Noora forms",
      body: "Improves dropdown keyboard focus.",
      url: "https://example.com/changelog/forms"
    })

    insert_drop!(domain, %{
      source_type: :rss,
      external_id: "search-rss-2",
      title: "Background sync",
      body: "Adjusts polling intervals.",
      url: "https://example.com/changelog/sync"
    })

    response =
      ListDrops.call(mcp_conn(user), %{"query" => "keyboard"})
      |> response_json()

    assert [%{"title" => "Noora forms"}] = response["drops"]
  end

  test "returns paginated results with metadata" do
    user = mcp_user()
    domain = create_domain!(%{name: "Hive", visibility: "public"})

    insert_drop!(domain, %{
      source_type: :rss,
      external_id: "page-rss-1",
      title: "First page",
      url: "https://example.com/changelog/page-1",
      published_at: ~U[2026-06-19 12:00:00Z]
    })

    insert_drop!(domain, %{
      source_type: :rss,
      external_id: "page-rss-2",
      title: "Second page",
      url: "https://example.com/changelog/page-2",
      published_at: ~U[2026-06-18 12:00:00Z]
    })

    response =
      ListDrops.call(mcp_conn(user), %{"page" => 2, "page_size" => 1})
      |> response_json()

    assert [%{"title" => "Second page"}] = response["drops"]

    assert response["meta"] == %{
             "current_page" => 2,
             "page_size" => 1,
             "total_entries" => 2,
             "total_pages" => 2
           }
  end

  defp project_id(domain), do: domain.projects |> List.first() |> Map.fetch!(:id)
end

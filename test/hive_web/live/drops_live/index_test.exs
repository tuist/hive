defmodule HiveWeb.DropsLive.IndexTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Drops
  alias Hive.Domains
  alias Hive.Domains.GitHubRepository
  alias Hive.Projects

  test "renders project and domains next to the title columns", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{name: "Tuist", visibility: "public"})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Generated projects",
        project_id: project.id,
        visibility: "public"
      })

    drop =
      insert_drop!(domain, %{
        title: "Generated project paths stay stable",
        body: "Generated projects now preserve path casing across machines.",
        version: "4.201.0-canary.19"
      })

    {:ok, _view, html} = live(conn, ~p"/drops")
    table = table_fragment(html)

    assert label_index(table, "Published") < label_index(table, "Title")
    assert label_index(table, "Title") < label_index(table, "Project")
    assert label_index(table, "Project") < label_index(table, "Domains")
    assert label_index(table, "Domains") < label_index(table, "Version")
    assert label_index(table, "Version") < label_index(table, "Source")
    assert html =~ "Tuist"
    assert html =~ "Generated projects"
    assert html =~ ~s(href="/drops/#{drop.number}")
  end

  test "renders the source project when a drop has no domains yet", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, project} = Projects.create_project(%{name: "Noora", visibility: "public"})

    repository =
      %GitHubRepository{}
      |> GitHubRepository.changeset(%{
        owner: "tuist",
        name: "noora",
        project_id: project.id
      })
      |> Hive.Repo.insert!()

    {:ok, _drop} =
      Drops.upsert_drop(%{
        source_type: :github_release,
        external_id: "tuist/noora@0.82.6",
        title: "Breadcrumb keyboard states",
        body: "Breadcrumb dropdown focus states now support keyboard navigation.",
        url: "https://github.com/tuist/noora/releases/tag/0.82.6",
        version: "noora@0.82.6",
        github_repository_id: repository.id,
        published_at: ~U[2026-06-20 12:00:00Z]
      })

    {:ok, _view, html} = live(conn, ~p"/drops")

    assert html =~ "Noora"
    assert html =~ "Unclassified"
  end

  defp insert_drop!(domain, attrs) do
    attrs =
      Map.merge(
        %{
          source_type: :github_release,
          external_id: "tuist/tuist@4.201.0-canary.19",
          title: "Drop",
          body: "Body",
          url: "https://github.com/tuist/tuist/releases/tag/4.201.0-canary.19",
          published_at: ~U[2026-06-20 12:00:00Z]
        },
        attrs
      )

    {:ok, drop} = Drops.upsert_drop(attrs)
    Drops.replace_drop_domains(drop, [domain.id])
    drop
  end

  defp table_fragment(html),
    do: html |> String.split(~s(id="drops-table"), parts: 2) |> List.last()

  defp label_index(html, label) do
    case :binary.match(html, label) do
      {index, _length} -> index
      :nomatch -> flunk("expected #{inspect(label)} in drops table")
    end
  end
end

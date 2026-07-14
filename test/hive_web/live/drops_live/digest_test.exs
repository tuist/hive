defmodule HiveWeb.DropsLive.DigestTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Drops.WeeklyDigest
  alias HiveWeb.OpenGraph

  test "lists narrated editions with feed discovery and row navigation", %{conn: conn} do
    digest =
      insert_digest!(%{
        week_start: ~D[2026-07-06],
        week_end: ~D[2026-07-10],
        title: "The work moved closer",
        summary: "This week connected faster builds with clearer operations."
      })

    {:ok, _view, html} = live(conn, ~p"/drops/digest")

    assert html =~ "Weekly digests"
    assert html =~ ~s(id="drops-digests-table")
    assert html =~ digest.title
    assert html =~ digest.summary
    assert html =~ "July 6 to July 10, 2026"
    assert html =~ "2 public drops"
    assert html =~ ~s(href="/drops/digest/2026-07-06")
    assert html =~ ~s(id="drops-digest-feeds-dropdown")
    assert html =~ "/drops/digest/atom.xml"
    assert html =~ "/drops/digest/rss.xml"

    assert html =~
             ~s(rel="alternate" type="application/atom+xml" title="Hive · Drops weekly digest" href="/drops/digest/atom.xml")

    assert {:ok, data} = advertised_open_graph_data(html)
    assert data.id == "drops-weekly-digests"
    assert data.path == "/drops/digest"
    assert data.title == "Weekly digests"
  end

  test "renders one narrated edition in the detail view", %{conn: conn} do
    digest =
      insert_digest!(%{
        week_start: ~D[2026-07-06],
        week_end: ~D[2026-07-10],
        title: "The work moved closer",
        summary: "This week connected faster builds with clearer operations.",
        body:
          "The interesting part was not one release. It was how [cache work](/drops/42) met the operational layer."
      })

    {:ok, _view, html} = live(conn, ~p"/drops/digest/2026-07-06")

    assert html =~ digest.title
    assert html =~ digest.summary
    assert html =~ ~s(href="/drops/42")
    assert html =~ "July 6 to July 10, 2026"
    assert html =~ "2 public drops"
    assert html =~ "All digests"
    assert html =~ ~s(href="/drops/digest")
    refute html =~ "Previous editions"

    assert {:ok, data} = advertised_open_graph_data(html)
    assert data.id == "drops-weekly-digest-2026-07-06"
    assert data.path == "/drops/digest/2026-07-06"
    assert data.title == digest.title
  end

  test "searches and filters editions", %{conn: conn} do
    insert_digest!(%{
      week_start: ~D[2025-12-22],
      week_end: ~D[2025-12-26],
      title: "A quieter foundation"
    })

    insert_digest!(%{
      week_start: ~D[2026-07-06],
      week_end: ~D[2026-07-10],
      title: "The visible feedback loop"
    })

    {:ok, view, html} = live(conn, ~p"/drops/digest")
    assert html =~ "Year"
    assert html =~ "A quieter foundation"
    assert html =~ "The visible feedback loop"

    html =
      view
      |> form("#drops-digests-search-form", search: %{query: "quieter"})
      |> render_change()

    assert html =~ "A quieter foundation"
    refute html =~ "The visible feedback loop"

    {:ok, _view, html} =
      live(conn, ~p"/drops/digest?filter_year_op===&filter_year_val=2026")

    assert html =~ "The visible feedback loop"
    refute html =~ "A quieter foundation"
    assert html =~ "2026"
  end

  test "paginates editions", %{conn: conn} do
    for index <- 0..10 do
      week_start = Date.add(~D[2026-01-05], index * 7)

      insert_digest!(%{
        week_start: week_start,
        week_end: Date.add(week_start, 4),
        title: "Narrated edition #{index + 1}",
        published_at: DateTime.new!(Date.add(week_start, 4), ~T[17:00:00], "Etc/UTC")
      })
    end

    {:ok, _view, first_page} = live(conn, ~p"/drops/digest")
    assert first_page =~ "Narrated edition 11"
    refute first_page =~ ">Narrated edition 1<"
    assert first_page =~ "Next"

    {:ok, _view, second_page} = live(conn, ~p"/drops/digest?page=2")
    assert second_page =~ "Narrated edition 1"
    refute second_page =~ "Narrated edition 11"
    assert second_page =~ "Prev"
  end

  test "renders a useful empty state before the first edition", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/drops/digest")

    assert html =~ "No weekly digests found"
    assert html =~ "wait for the next narrated edition"
    assert html =~ "/drops/digest/atom.xml"
  end

  test "redirects a missing edition to the digest index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/drops/digest"}}} =
             live(conn, ~p"/drops/digest/2025-01-06")
  end

  defp insert_digest!(attrs) do
    defaults = %{
      week_start: ~D[2026-07-06],
      week_end: ~D[2026-07-10],
      status: :published,
      title: "Weekly edition",
      summary: "A connected summary.",
      body: "A connected narration.",
      drop_ids: [Ecto.UUID.generate(), Ecto.UUID.generate()],
      published_at: ~U[2026-07-10 17:00:00Z]
    }

    %WeeklyDigest{}
    |> WeeklyDigest.changeset(Map.merge(defaults, attrs))
    |> Hive.Repo.insert!()
  end

  defp advertised_open_graph_data(html) do
    with [_, image] <- Regex.run(~r/property="og:image" content="([^"]+)"/, html),
         %URI{query: query} when is_binary(query) <- URI.parse(image),
         %{"token" => token} <- URI.decode_query(query) do
      OpenGraph.verify_token(HiveWeb.Endpoint, token)
    else
      _other -> {:error, :missing_open_graph_image}
    end
  end
end

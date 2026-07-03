defmodule Hive.Drops.RssSyncerTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  import Ecto.Query

  alias Hive.Drops
  alias Hive.Drops.DomainClassificationWorker
  alias Hive.Drops.Drop
  alias Hive.Drops.RssSyncer
  alias Hive.Domains
  alias Hive.Projects

  test "sync_source/1 ingests entries and enqueues classification" do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Domain #{System.unique_integer([:positive])}",
        project_id: project.id,
        visibility: "public"
      })

    {:ok, source} =
      Drops.create_drop_source(%{
        project_id: project.id,
        url: "https://example.com/feed.xml",
        label: "Example changelog"
      })

    expect(Req, :get, fn "https://example.com/feed.xml", _opts ->
      {:ok,
       %{
         status: 200,
         body: """
         <?xml version="1.0" encoding="UTF-8"?>
         <rss version="2.0">
           <channel>
             <item>
               <guid>release-1</guid>
               <title>Release 1</title>
               <link>https://example.com/releases/1</link>
               <description>Shipped a useful change.</description>
               <pubDate>Fri, 03 Jul 2026 09:00:00 GMT</pubDate>
             </item>
           </channel>
         </rss>
         """
       }}
    end)

    assert :ok = RssSyncer.sync_source(source)

    assert [%Drop{} = drop] = Repo.all(from(drop in Drop))
    assert drop.source_type == :rss
    assert drop.drop_source_id == source.id
    assert drop.external_id == "release-1"
    assert drop.title == "Release 1"
    assert drop.url == "https://example.com/releases/1"
    refute drop.classified_at

    assert [%Oban.Job{args: %{"drop_id" => drop_id}}] =
             all_enqueued(worker: DomainClassificationWorker)

    assert drop_id == drop.id
    assert :ok = perform_job(DomainClassificationWorker, %{"drop_id" => drop.id})

    drop = Repo.get!(Drop, drop.id)
    assert drop.classified_at
    assert [%{id: domain_id}] = Repo.preload(drop, :domains).domains
    assert domain_id == domain.id
  end

  test "perform/1 syncs pollable sources" do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    {:ok, source} =
      Drops.create_drop_source(%{
        project_id: project.id,
        url: "https://example.com/feed.xml",
        label: "Example changelog"
      })

    expect(Req, :get, fn "https://example.com/feed.xml", _opts ->
      {:ok,
       %{
         status: 200,
         body: """
         <?xml version="1.0" encoding="UTF-8"?>
         <rss version="2.0">
           <channel>
             <item>
               <guid>release-1</guid>
               <title>Release 1</title>
               <link>https://example.com/releases/1</link>
             </item>
           </channel>
         </rss>
         """
       }}
    end)

    assert :ok = RssSyncer.perform(%Oban.Job{})

    assert [%Drop{drop_source_id: drop_source_id}] = Repo.all(from(drop in Drop))
    assert drop_source_id == source.id
  end

  test "enqueue_source/1 enqueues a one-source sync job" do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    {:ok, source} =
      Drops.create_drop_source(%{
        project_id: project.id,
        url: "https://example.com/feed.xml",
        label: "Example changelog"
      })

    assert {:ok, %Oban.Job{}} = RssSyncer.enqueue_source(source)

    assert [%Oban.Job{args: %{"drop_source_id" => drop_source_id}}] =
             all_enqueued(worker: RssSyncer)

    assert drop_source_id == source.id
  end
end

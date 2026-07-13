defmodule Hive.Drops.ReleaseDropItemsTest do
  use ExUnit.Case, async: true

  alias Hive.Drops.Agents.ReleaseDropItemAgent
  alias Hive.Drops.ReleaseDropItems
  alias Hive.GitHub.Releases
  alias Hive.Domains.GitHubRepository

  test "release drop item agent receives pre-fetched evidence without tools" do
    assert ReleaseDropItemAgent.tools() == []
  end

  test "generates normalized items from the agent output" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}

    release = %Releases{
      tag_name: "v1.2.0",
      name: "Hive 1.2.0",
      body: """
      ## What's changed

      - Faster cache warmups in #41
      - Stable generated project paths in https://github.com/tuist/hive/pull/42.
      """,
      html_url: "https://github.com/tuist/hive/releases/tag/v1.2.0",
      published_at: "2026-06-18T09:30:00Z"
    }

    runner = fn input ->
      assert input.release.repository == "tuist/hive"

      assert input.release.reference_urls == [
               "https://github.com/tuist/hive/pull/42",
               "https://github.com/tuist/hive/issues/41"
             ]

      assert Enum.map(input.release.references, & &1.url) == input.release.reference_urls
      assert Enum.all?(input.release.references, &(&1.content == "Fetched release evidence"))

      {:ok,
       %{
         "items" => [
           %{
             "title" => "Project cache warmups finish faster",
             "body" => "Warmups now reuse existing cache metadata before planning work.",
             "source_urls" => [
               "https://github.com/tuist/hive/issues/41",
               "https://github.com/tuist/hive/issues/41"
             ]
           },
           %{
             "title" => "",
             "body" => "This invalid item should be ignored.",
             "source_urls" => ["https://github.com/tuist/hive/pull/42"]
           },
           %{
             "title" => "Private link",
             "body" => "This invalid item should also be ignored.",
             "source_urls" => ["http://localhost/private"]
           }
         ]
       }}
    end

    fetcher = fn _url ->
      {:ok,
       %{
         final_url: "https://github.com/tuist/hive/issues/41",
         title: "Reference",
         content_type: "text/html",
         content: "Fetched release evidence",
         truncated: false
       }}
    end

    assert {:ok,
            [
              %{
                title: "Project cache warmups finish faster",
                body: "Warmups now reuse existing cache metadata before planning work.",
                source_urls: ["https://github.com/tuist/hive/issues/41"]
              }
            ]} =
             ReleaseDropItems.generate(repository, release,
               agents_enabled?: fn -> true end,
               fetcher: fetcher,
               runner: runner
             )
  end

  test "fetches a bounded set of links discovered in release evidence" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}
    seed_url = "https://example.com/release-notes"
    release = %Releases{body: "See #{seed_url}"}

    discovered_urls =
      Enum.map(1..12, &"https://example.com/evidence/#{&1}")

    fetcher = fn
      ^seed_url ->
        {:ok,
         %{
           content: Enum.join(discovered_urls, "\n"),
           final_url: seed_url,
           content_type: "text/plain"
         }}

      url ->
        {:ok, %{content: "Evidence for #{url}", final_url: url, content_type: "text/plain"}}
    end

    runner = fn input ->
      assert Enum.map(input.release.references, & &1.url) ==
               [seed_url | Enum.take(discovered_urls, 10)]

      {:ok, %{items: []}}
    end

    assert {:ok, []} =
             ReleaseDropItems.generate(repository, release,
               agents_enabled?: fn -> true end,
               fetcher: fetcher,
               runner: runner
             )
  end

  test "skips when agents are disabled" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}
    release = %Releases{body: "See https://github.com/tuist/hive/issues/41"}

    assert :skipped =
             ReleaseDropItems.generate(repository, release, agents_enabled?: fn -> false end)
  end
end

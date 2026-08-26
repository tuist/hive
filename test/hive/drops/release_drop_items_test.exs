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

      assert Enum.map(input.release.references, & &1.url) == [
               "https://github.com/tuist/hive/pull/42",
               "https://github.com/tuist/hive/issues/41"
             ]

      assert Enum.all?(input.release.references, &(&1.content == "Fetched release evidence"))

      assert Enum.all?(
               input.release.references,
               &(Enum.sort(Map.keys(&1)) == [:content, :title, :url])
             )

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

    fetcher = fn url ->
      {:ok,
       %{
         final_url: url,
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

  test "keeps failed reference metadata out of the model input" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}
    successful_url = "https://example.com/shipped"
    failed_url = "https://example.com/unavailable"
    release = %Releases{body: "See #{successful_url} and #{failed_url}"}

    fetcher = fn
      ^successful_url ->
        {:ok, %{content: "User-facing evidence", final_url: successful_url}}

      ^failed_url ->
        {:error, "upstream unavailable"}
    end

    runner = fn input ->
      assert input.release.references == [
               %{url: successful_url, content: "User-facing evidence"}
             ]

      {:ok, %{items: []}}
    end

    assert {:ok, []} =
             ReleaseDropItems.generate(repository, release,
               agents_enabled?: fn -> true end,
               fetcher: fetcher,
               runner: runner
             )
  end

  test "fetches links discovered in release evidence" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}
    seed_url = "https://example.com/release-notes"
    release = %Releases{body: "See #{seed_url}"}

    discovered_urls =
      Enum.map(1..8, &"https://example.com/evidence/#{&1}")

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
               [seed_url | discovered_urls]

      {:ok, %{items: []}}
    end

    assert {:ok, []} =
             ReleaseDropItems.generate(repository, release,
               agents_enabled?: fn -> true end,
               fetcher: fetcher,
               runner: runner
             )
  end

  test "recursively fetches links discovered in fetched evidence" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}
    seed_url = "https://example.com/release-notes"
    second_url = "https://example.com/evidence/second"
    third_url = "https://example.com/evidence/third"
    release = %Releases{body: "See #{seed_url}"}

    fetcher = fn
      ^seed_url ->
        {:ok, %{content: second_url, final_url: seed_url, content_type: "text/plain"}}

      ^second_url ->
        {:ok, %{content: third_url, final_url: second_url, content_type: "text/plain"}}

      ^third_url ->
        {:ok, %{content: "Final evidence", final_url: third_url, content_type: "text/plain"}}
    end

    runner = fn input ->
      assert Enum.map(input.release.references, & &1.url) == [seed_url, second_url, third_url]
      {:ok, %{items: []}}
    end

    assert {:ok, []} =
             ReleaseDropItems.generate(repository, release,
               agents_enabled?: fn -> true end,
               fetcher: fetcher,
               runner: runner
             )
  end

  test "bounds the complete release evidence traversal" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}
    seed_url = "https://example.com/release-notes"
    release = %Releases{body: "See #{seed_url}"}
    discovered_urls = Enum.map(1..55, &"https://example.com/evidence/#{&1}")

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
               [seed_url | Enum.take(discovered_urls, 11)]

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

  describe "reference budget" do
    setup do
      repository = %GitHubRepository{owner: "tuist", name: "hive"}

      release = %Releases{
        tag_name: "v2.0.0",
        name: "Hive 2.0.0",
        body: Enum.map_join(1..40, "\n", &"- See https://example.com/doc-#{&1}"),
        html_url: "https://github.com/tuist/hive/releases/tag/v2.0.0",
        published_at: "2026-08-26T09:30:00Z"
      }

      fetcher = fn url ->
        {:ok, %{content: String.duplicate("x", 7_000), title: "Doc", final_url: url}}
      end

      {:ok, repository: repository, release: release, fetcher: fetcher}
    end

    test "bounds the characters reference content contributes to the prompt", ctx do
      test_pid = self()

      runner = fn input ->
        total =
          input.release.references
          |> Enum.map(&String.length(&1.content))
          |> Enum.sum()

        send(test_pid, {:budget, length(input.release.references), total})
        {:ok, %{items: []}}
      end

      assert {:ok, []} =
               ReleaseDropItems.generate(ctx.repository, ctx.release,
                 agents_enabled?: fn -> true end,
                 fetcher: ctx.fetcher,
                 runner: runner
               )

      assert_received {:budget, count, total}

      # Without a budget this release would carry 40 documents of 12k characters.
      assert total <= 60_000
      assert count <= 12
    end

    test "marks the reference that straddles the limit as truncated", ctx do
      test_pid = self()

      runner = fn input ->
        send(test_pid, {:refs, input.release.references})
        {:ok, %{items: []}}
      end

      assert {:ok, []} =
               ReleaseDropItems.generate(ctx.repository, ctx.release,
                 agents_enabled?: fn -> true end,
                 fetcher: ctx.fetcher,
                 runner: runner
               )

      assert_received {:refs, references}

      assert Enum.any?(references, &Map.get(&1, :truncated))
    end
  end
end

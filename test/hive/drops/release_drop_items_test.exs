defmodule Hive.Drops.ReleaseDropItemsTest do
  use ExUnit.Case, async: true

  alias Hive.Agents.Tools.FetchUrlContent
  alias Hive.Drops.Agents.ReleaseDropItemAgent
  alias Hive.Drops.ReleaseDropItems
  alias Hive.GitHub.Releases
  alias Hive.Meadows.GitHubRepository

  test "release drop item agent can fetch URL content" do
    assert ReleaseDropItemAgent.tools() == [FetchUrlContent]
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

defmodule Hive.Drops.ReleaseDropItemsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Hive.Agents
  alias Hive.Agents.Sessions
  alias Hive.Domains.GitHubRepository
  alias Hive.Drops.Agents.ReleaseDropItemAgent
  alias Hive.Drops.ReleaseDropItems
  alias Hive.GitHub.Issues
  alias Hive.GitHub.Releases

  test "release drop generation has no model tools" do
    assert ReleaseDropItemAgent.tools() == []
  end

  test "builds individual feature drops from directly referenced GitHub work" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}

    release = %Releases{
      tag_name: "v1.2.0",
      name: "Hive 1.2.0",
      body: "Cache warmups are faster in #41. Generated paths are stable in #42.",
      html_url: "https://github.com/tuist/hive/releases/tag/v1.2.0"
    }

    issue_fetcher = fn
      %GitHubRepository{owner: "tuist", name: "hive"}, 41 ->
        {:ok,
         %Issues{
           number: 41,
           title: "Faster cache warmups",
           body: "Projects reuse cache metadata before planning work.",
           state: "closed",
           html_url: "https://github.com/tuist/hive/issues/41"
         }}

      %GitHubRepository{owner: "tuist", name: "hive"}, 42 ->
        {:ok,
         %Issues{
           number: 42,
           title: "Stable generated paths",
           body: "Generated projects preserve path casing across machines.",
           state: "closed",
           html_url: "https://github.com/tuist/hive/pull/42"
         }}
    end

    runner = fn %{release: input} ->
      assert input.repository == "tuist/hive"
      assert input.tag == "v1.2.0"

      assert input.references == [
               %{
                 url: "https://github.com/tuist/hive/issues/41",
                 number: 41,
                 title: "Faster cache warmups",
                 body: "Projects reuse cache metadata before planning work.",
                 state: "closed"
               },
               %{
                 url: "https://github.com/tuist/hive/pull/42",
                 number: 42,
                 title: "Stable generated paths",
                 body: "Generated projects preserve path casing across machines.",
                 state: "closed"
               }
             ]

      {:ok,
       %{
         items: [
           %{
             title: "Faster cache warmups",
             body: "Projects now start work with reusable cache metadata.",
             source_urls: ["https://github.com/tuist/hive/issues/41"]
           },
           %{
             title: "Stable generated paths",
             body: "Generated projects preserve path casing across machines.",
             source_urls: ["https://github.com/tuist/hive/pull/42"]
           }
         ]
       }}
    end

    assert {:ok, items} =
             ReleaseDropItems.generate(repository, release,
               agents_enabled?: fn -> true end,
               issue_fetcher: issue_fetcher,
               runner: runner
             )

    assert Enum.map(items, & &1.title) == ["Faster cache warmups", "Stable generated paths"]
  end

  test "does not call the model when a release has no direct GitHub evidence" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}
    release = %Releases{tag_name: "v1.2.0", body: "Improves project generation."}

    assert {:ok, []} =
             ReleaseDropItems.generate(repository, release,
               agents_enabled?: fn -> true end,
               runner: fn _input -> flunk("the model should not run") end
             )
  end

  test "skips generation when agents are disabled" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}
    release = %Releases{tag_name: "v1.2.0", body: "See #41."}

    assert :skipped =
             ReleaseDropItems.generate(repository, release,
               agents_enabled?: fn -> false end,
               runner: fn _input -> flunk("the model should not run") end
             )
  end

  test "limits the prompt to the release and six trimmed GitHub references" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}
    body = Enum.map_join(1..8, " ", &"##{&1}") <> String.duplicate("x", 7_000)
    release = %Releases{tag_name: "v1.2.0", body: body}

    issue_fetcher = fn _repository, number ->
      {:ok,
       %Issues{
         number: number,
         title: "Issue #{number}",
         body: String.duplicate("a", 2_100),
         state: :closed,
         html_url: "https://github.com/tuist/hive/issues/#{number}"
       }}
    end

    runner = fn %{release: input} ->
      assert String.length(input.body) == 6_000
      assert length(input.references) == 6
      assert Enum.all?(input.references, &(String.length(&1.body) == 2_000))
      {:ok, %{items: []}}
    end

    assert {:ok, []} =
             ReleaseDropItems.generate(repository, release,
               agents_enabled?: fn -> true end,
               issue_fetcher: issue_fetcher,
               runner: runner
             )
  end

  test "uses one model turn and normalizes the structured result" do
    repository = %GitHubRepository{owner: "tuist", name: "hive"}
    release = %Releases{tag_name: "v1.2.0", body: "See #41."}

    stub(Agents, :enabled?, fn -> true end)

    expect(Sessions, :run_operation, fn ReleaseDropItemAgent,
                                        :generate_drop_items,
                                        %{release: %{references: [_reference]}},
                                        agent_opts ->
      assert agent_opts[:max_turns] == 1

      {:ok,
       %{
         "items" => [
           %{
             "title" => "A feature",
             "body" => "A user-facing change.",
             "source_urls" => [
               "https://github.com/tuist/hive/issues/41",
               "https://github.com/tuist/hive/issues/999"
             ]
           }
         ]
       }}
    end)

    assert {:ok,
            [
              %{
                title: "A feature",
                body: "A user-facing change.",
                source_urls: ["https://github.com/tuist/hive/issues/41"]
              }
            ]} =
             ReleaseDropItems.generate(repository, release,
               issue_fetcher: fn _repository, 41 ->
                 {:ok,
                  %Issues{
                    number: 41,
                    title: "A feature",
                    body: "Evidence.",
                    state: "closed",
                    html_url: "https://github.com/tuist/hive/issues/41"
                  }}
               end,
               agent_opts: [max_turns: 3]
             )
  end
end

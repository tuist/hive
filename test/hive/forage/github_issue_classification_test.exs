defmodule Hive.Forage.GitHubIssueClassificationTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Forage
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueClassification
  alias Hive.Forage.GitHubIssueMeadow
  alias Hive.Meadows

  defp unique, do: System.unique_integer([:positive])

  defp create_meadow!(attrs) do
    {:ok, meadow} = Meadows.create_meadow(attrs)
    meadow
  end

  defp create_meadow_with_new_repo!(name_prefix) do
    suffix = unique()

    create_meadow!(%{
      name: "#{name_prefix}-#{suffix}",
      visibility: "public",
      github_repository_owner: "owner#{suffix}",
      github_repository_name: "repo#{suffix}",
      github_repository_visibility: "public"
    })
  end

  defp attach_meadow!(name_prefix, repository) do
    suffix = unique()

    create_meadow!(%{
      name: "#{name_prefix}-#{suffix}",
      visibility: "public",
      github_repository_owner: repository.owner,
      github_repository_name: repository.name,
      github_repository_visibility: "public"
    })
  end

  defp seed_issue!(meadow) do
    repo = hd(meadow.github_repositories)

    Forage.reconcile_repository_github_issues(repo, [
      %{number: 1, title: "An issue", body: "Some body"}
    ])

    {repo, Repo.get_by!(GitHubIssue, github_repository_id: repo.id, number: 1)}
  end

  test "links every candidate meadow when the LLM is unavailable" do
    meadow_a = create_meadow_with_new_repo!("alpha")
    repo = hd(meadow_a.github_repositories)
    meadow_b = attach_meadow!("beta", repo)

    {_repo, issue} = seed_issue!(meadow_a)

    assert {:ok, ids} =
             GitHubIssueClassification.classify(issue.id, agents_enabled?: fn -> false end)

    assert Enum.sort(ids) == Enum.sort([meadow_a.id, meadow_b.id])

    persisted = Repo.preload(Repo.get!(GitHubIssue, issue.id), :meadows)

    assert Enum.sort(Enum.map(persisted.meadows, & &1.id)) ==
             Enum.sort([meadow_a.id, meadow_b.id])

    refute is_nil(persisted.classified_at)
  end

  test "keeps only the meadow ids the agent picked from the candidate set" do
    meadow_a = create_meadow_with_new_repo!("alpha")
    repo = hd(meadow_a.github_repositories)
    meadow_b = attach_meadow!("beta", repo)
    unrelated = create_meadow_with_new_repo!("unrelated")

    {_repo, issue} = seed_issue!(meadow_a)

    runner = fn _input ->
      {:ok, %{meadow_ids: [meadow_b.id, unrelated.id, "not-a-meadow"]}}
    end

    assert {:ok, [chosen]} =
             GitHubIssueClassification.classify(issue.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert chosen == meadow_b.id

    persisted = Repo.preload(Repo.get!(GitHubIssue, issue.id), :meadows)
    assert Enum.map(persisted.meadows, & &1.id) == [meadow_b.id]
  end

  test "produces no links when the agent returns an empty list" do
    meadow = create_meadow_with_new_repo!("alpha")
    {_repo, issue} = seed_issue!(meadow)

    runner = fn _input -> {:ok, %{meadow_ids: []}} end

    assert {:ok, []} =
             GitHubIssueClassification.classify(issue.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert [] = Repo.all(GitHubIssueMeadow)
    refute is_nil(Repo.get!(GitHubIssue, issue.id).classified_at)
  end

  test "returns the LLM error when the runner fails" do
    meadow = create_meadow_with_new_repo!("alpha")
    {_repo, issue} = seed_issue!(meadow)

    runner = fn _input -> {:error, :ratelimited} end

    assert {:error, :ratelimited} =
             GitHubIssueClassification.classify(issue.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )
  end

  test "falls back to every candidate when the LLM is not configured at runtime" do
    meadow = create_meadow_with_new_repo!("alpha")
    {_repo, issue} = seed_issue!(meadow)

    runner = fn _input -> {:error, :llm_not_configured} end

    assert {:ok, [chosen]} =
             GitHubIssueClassification.classify(issue.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert chosen == meadow.id
  end

  test "returns :not_found for an unknown id" do
    assert {:error, :not_found} =
             GitHubIssueClassification.classify("00000000-0000-0000-0000-000000000001")
  end
end

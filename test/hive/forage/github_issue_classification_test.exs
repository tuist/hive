defmodule Hive.Forage.GitHubIssueClassificationTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Forage
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueClassification
  alias Hive.Forage.GitHubIssueDomain
  alias Hive.Domains
  alias Hive.GitHub.Issues
  alias Hive.Projects

  defp unique, do: System.unique_integer([:positive])

  defp create_domain!(attrs) do
    attrs =
      Map.put_new_lazy(attrs, :project_id, fn ->
        {:ok, project} = Projects.create_project(%{name: "Project #{unique()}"})
        project.id
      end)

    {:ok, domain} = Domains.create_domain(attrs)
    domain
  end

  defp create_domain_with_new_repo!(name_prefix) do
    suffix = unique()

    create_domain!(%{
      name: "#{name_prefix}-#{suffix}",
      visibility: "public",
      github_repository_owner: "owner#{suffix}",
      github_repository_name: "repo#{suffix}",
      github_repository_visibility: "public"
    })
  end

  defp attach_domain!(name_prefix, repository) do
    suffix = unique()
    repository = Repo.preload(repository, :project)

    create_domain!(%{
      name: "#{name_prefix}-#{suffix}",
      visibility: "public",
      project_id: repository.project_id
    })
  end

  defp seed_issue!(domain) do
    repo = github_repository_for_domain!(domain)

    Forage.reconcile_repository_github_issues(repo, [
      %{number: 1, title: "An issue", body: "Some body"}
    ])

    {repo, Repo.get_by!(GitHubIssue, github_repository_id: repo.id, number: 1)}
  end

  test "links every candidate domain when the LLM is unavailable" do
    domain_a = create_domain_with_new_repo!("alpha")
    repo = github_repository_for_domain!(domain_a)
    domain_b = attach_domain!("beta", repo)

    {_repo, issue} = seed_issue!(domain_a)

    assert {:ok, ids} =
             GitHubIssueClassification.classify(issue.id, agents_enabled?: fn -> false end)

    assert Enum.sort(ids) == Enum.sort([domain_a.id, domain_b.id])

    persisted = Repo.preload(Repo.get!(GitHubIssue, issue.id), :domains)

    assert Enum.sort(Enum.map(persisted.domains, & &1.id)) ==
             Enum.sort([domain_a.id, domain_b.id])

    refute is_nil(persisted.classified_at)
  end

  test "keeps only the domain ids the agent picked from the candidate set" do
    domain_a = create_domain_with_new_repo!("alpha")
    repo = github_repository_for_domain!(domain_a)
    domain_b = attach_domain!("beta", repo)
    unrelated = create_domain_with_new_repo!("unrelated")

    {_repo, issue} = seed_issue!(domain_a)

    runner = fn _input ->
      {:ok, %{domain_ids: [domain_b.id, unrelated.id, "not-a-domain"]}}
    end

    assert {:ok, [chosen]} =
             GitHubIssueClassification.classify(issue.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert chosen == domain_b.id

    persisted = Repo.preload(Repo.get!(GitHubIssue, issue.id), :domains)
    assert Enum.map(persisted.domains, & &1.id) == [domain_b.id]
  end

  test "produces no links when the agent returns an empty list" do
    domain = create_domain_with_new_repo!("alpha")
    {_repo, issue} = seed_issue!(domain)

    runner = fn _input -> {:ok, %{domain_ids: []}} end

    assert {:ok, []} =
             GitHubIssueClassification.classify(issue.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert [] = Repo.all(GitHubIssueDomain)
    refute is_nil(Repo.get!(GitHubIssue, issue.id).classified_at)
  end

  test "returns the LLM error when the runner fails" do
    domain = create_domain_with_new_repo!("alpha")
    {_repo, issue} = seed_issue!(domain)

    runner = fn _input -> {:error, :ratelimited} end

    assert {:error, :ratelimited} =
             GitHubIssueClassification.classify(issue.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )
  end

  test "falls back to every candidate when the LLM is not configured at runtime" do
    domain = create_domain_with_new_repo!("alpha")
    {_repo, issue} = seed_issue!(domain)

    runner = fn _input -> {:error, :llm_not_configured} end

    assert {:ok, [chosen]} =
             GitHubIssueClassification.classify(issue.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert chosen == domain.id
  end

  test "returns :not_found for an unknown id" do
    assert {:error, :not_found} =
             GitHubIssueClassification.classify("00000000-0000-0000-0000-000000000001")
  end

  test "leaves classified_at nil when the repository has no domain attached" do
    domain = create_domain_with_new_repo!("orphan")
    repo = github_repository_for_domain!(domain)

    issue =
      Repo.insert!(
        GitHubIssue.changeset(%GitHubIssue{}, %{
          github_repository_id: repo.id,
          number: 1,
          title: "Lonely issue",
          body: nil,
          state: :open
        })
      )

    Repo.delete!(domain)

    assert {:ok, []} =
             GitHubIssueClassification.classify(issue.id, agents_enabled?: fn -> false end)

    refreshed = Repo.get!(GitHubIssue, issue.id)
    assert is_nil(refreshed.classified_at)
    assert [] = Repo.all(GitHubIssueDomain)
  end

  test "keeps terminal failures for unchanged content and retries changed content" do
    stub(Hive.Agents, :enabled?, fn -> false end)

    domain = create_domain_with_new_repo!("retry")
    repository = github_repository_for_domain!(domain)

    issue =
      Repo.insert!(
        GitHubIssue.changeset(%GitHubIssue{}, %{
          github_repository_id: repository.id,
          number: 7,
          title: "Original",
          body: "Body",
          state: :open
        })
      )

    GitHubIssueClassification.mark_failed(issue.id, :llm_credit_limit)

    assert {:ok, _issue} =
             Forage.upsert_repository_github_issue(repository, %Issues{
               number: 7,
               title: "Original",
               body: "Body",
               state: "open"
             })

    unchanged = Repo.get!(GitHubIssue, issue.id)
    assert unchanged.classification_failure == "llm_credit_limit"
    assert is_nil(unchanged.classified_at)

    assert {:ok, _issue} =
             Forage.upsert_repository_github_issue(repository, %Issues{
               number: 7,
               title: "Updated",
               body: "Body",
               state: "open"
             })

    changed = Repo.get!(GitHubIssue, issue.id)
    assert changed.title == "Updated"
    assert is_nil(changed.classification_failure)
    assert is_nil(changed.classification_failed_at)
    assert %DateTime{} = changed.classified_at
  end
end

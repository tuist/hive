defmodule Hive.Forage.GitHubIssueSyncerTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Forage
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueSyncer
  alias Hive.GitHub.Client
  alias Hive.GitHub.Issues
  alias Hive.Domains
  alias Hive.Projects

  defp unique, do: System.unique_integer([:positive])

  defp setup_domain! do
    suffix = unique()

    {:ok, domain} =
      Domains.create_domain(%{
        name: "hive-syncer-#{suffix}",
        project_id: create_project!().id,
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    domain
  end

  defp create_project! do
    {:ok, project} = Projects.create_project(%{name: "Project #{unique()}"})
    project
  end

  defp create_repository_for_project!(project) do
    suffix = unique()

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{
        owner: "owner#{suffix}",
        name: "repo#{suffix}",
        visibility: "public"
      })

    repository
  end

  test "skips the sync when the GitHub App is not configured" do
    stub(Client, :config, fn -> {:error, {:not_configured, [:app_id]}} end)
    setup_domain!()

    assert :skipped = GitHubIssueSyncer.sync_now()
    assert Repo.aggregate(GitHubIssue, :count) == 0
  end

  test "perform/1 completes when the GitHub App is not configured" do
    stub(Client, :config, fn -> {:error, {:not_configured, [:app_id]}} end)
    setup_domain!()

    assert :ok = GitHubIssueSyncer.perform(%Oban.Job{})
    assert Repo.aggregate(GitHubIssue, :count) == 0
  end

  test "perform/1 enqueues one sync job per GitHub issue repository" do
    domain = setup_domain!()
    domain_repository = github_repository_for_domain!(domain)
    project = create_project!()
    project_repository = create_repository_for_project!(project)

    stub(Client, :config, fn -> {:ok, %Client.Config{}} end)

    assert :ok = GitHubIssueSyncer.perform(%Oban.Job{})

    repository_ids =
      all_enqueued(worker: GitHubIssueSyncer)
      |> Enum.map(& &1.args["repository_id"])
      |> Enum.sort()

    assert repository_ids == Enum.sort([domain_repository.id, project_repository.id])
  end

  test "enqueue_repository/1 keeps one incomplete sync job per repository" do
    domain = setup_domain!()
    repository = github_repository_for_domain!(domain)

    assert {:ok, first_job} = GitHubIssueSyncer.enqueue_repository(repository)
    assert {:ok, second_job} = GitHubIssueSyncer.enqueue_repository(repository)

    assert first_job.id == second_job.id
    assert second_job.conflict?
  end

  test "perform/1 syncs only the repository named in the job arguments" do
    domain = setup_domain!()
    repository = github_repository_for_domain!(domain)
    other_repository = create_repository_for_project!(create_project!())

    stub(Client, :config, fn -> {:ok, %Client.Config{}} end)

    stub(Issues, :list_open_issues, fn ^repository ->
      {:ok, [%Issues{number: 1, title: "Repository issue", body: "Body"}]}
    end)

    assert :ok = GitHubIssueSyncer.perform(%Oban.Job{args: %{"repository_id" => repository.id}})

    assert %GitHubIssue{title: "Repository issue"} =
             Repo.get_by(GitHubIssue, github_repository_id: repository.id, number: 1)

    refute Repo.get_by(GitHubIssue, github_repository_id: other_repository.id, number: 1)
  end

  test "perform/1 ignores stale repository sync jobs" do
    assert :ok =
             GitHubIssueSyncer.perform(%Oban.Job{
               args: %{"repository_id" => "00000000-0000-0000-0000-000000000001"}
             })
  end

  test "sentry_check_in_configuration/1 gives the lightweight scheduler a small grace window" do
    assert [monitor_config: [checkin_margin: 5, max_runtime: 5]] =
             GitHubIssueSyncer.sentry_check_in_configuration(%Oban.Job{})
  end

  test "upserts new issues and deletes issues that disappeared upstream" do
    domain = setup_domain!()
    repository = github_repository_for_domain!(domain)

    stub(Client, :config, fn -> {:ok, %Client.Config{}} end)

    stub(Issues, :list_open_issues, fn ^repository ->
      {:ok,
       [
         %Issues{number: 1, title: "Initial title", body: "Initial body"},
         %Issues{number: 2, title: "Second issue", body: "Body two"}
       ]}
    end)

    assert :ok = GitHubIssueSyncer.sync_now()

    assert [first, second] = Repo.all(from issue in GitHubIssue, order_by: [asc: issue.number])
    assert first.title == "Initial title"
    assert second.title == "Second issue"

    stub(Issues, :list_open_issues, fn ^repository ->
      {:ok, [%Issues{number: 1, title: "Updated title", body: "Updated body"}]}
    end)

    assert :ok = GitHubIssueSyncer.sync_now()

    assert [remaining] = Repo.all(GitHubIssue)
    assert remaining.number == 1
    assert remaining.title == "Updated title"
  end

  test "syncs repositories attached to projects before any domains exist" do
    project = create_project!()
    repository = create_repository_for_project!(project)

    stub(Client, :config, fn -> {:ok, %Client.Config{}} end)

    stub(Issues, :list_open_issues, fn ^repository ->
      {:ok, [%Issues{number: 1, title: "Bootstrap domains", body: "New issue signal"}]}
    end)

    assert :ok = GitHubIssueSyncer.sync_now()

    assert %GitHubIssue{title: "Bootstrap domains", classified_at: nil} =
             Repo.get_by(GitHubIssue, github_repository_id: repository.id, number: 1)
  end

  test "keeps closed issues that were linked from release drops" do
    domain = setup_domain!()
    repository = github_repository_for_domain!(domain)

    assert {:ok, %GitHubIssue{state: :closed}} =
             Forage.upsert_repository_github_issue(repository, %Issues{
               number: 10,
               title: "Released change",
               body: "This was addressed by a release.",
               state: "closed"
             })

    assert :ok = Forage.reconcile_repository_github_issues(repository, [])

    assert %GitHubIssue{title: "Released change", state: :closed} =
             Repo.get_by(GitHubIssue, github_repository_id: repository.id, number: 10)
  end

  test "list_github_issues_for_user/1 returns issues with their domain/repo context" do
    domain = setup_domain!()
    repository = github_repository_for_domain!(domain)

    Forage.reconcile_repository_github_issues(repository, [
      %{number: 1, title: "Hello", body: "World"}
    ])

    assert [{returned_repo, issue, returned_domains}] = Forage.list_github_issues_for_user(nil)
    assert returned_repo.id == repository.id
    assert issue.title == "Hello"
    assert Enum.map(returned_domains, & &1.id) == [domain.id]
  end
end

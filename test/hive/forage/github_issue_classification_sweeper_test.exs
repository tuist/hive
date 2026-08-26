defmodule Hive.Forage.GitHubIssueClassificationSweeperTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueClassification
  alias Hive.Forage.GitHubIssueClassificationSweeper
  alias Hive.Forage.GitHubIssueClassificationWorker
  alias Hive.Domains
  alias Hive.Projects

  defp unique, do: System.unique_integer([:positive])

  defp create_repository! do
    suffix = unique()

    {:ok, domain} =
      Domains.create_domain(%{
        name: "sweeper-#{suffix}",
        project_id: create_project!().id,
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo#{suffix}",
        github_repository_visibility: "public"
      })

    github_repository_for_domain!(domain)
  end

  defp create_project! do
    {:ok, project} = Projects.create_project(%{name: "Project #{unique()}"})
    project
  end

  defp insert_issue!(repository, number, attrs \\ %{}) do
    Repo.insert!(
      %GitHubIssue{}
      |> GitHubIssue.changeset(
        Map.merge(
          %{
            github_repository_id: repository.id,
            number: number,
            title: "Issue #{number}",
            body: "Body #{number}",
            state: :open
          },
          attrs
        )
      )
    )
  end

  test "perform/1 enqueues a classification job for each unclassified issue" do
    stub(Hive.Agents, :enabled?, fn -> true end)

    repository = create_repository!()

    classified_at = DateTime.utc_now() |> DateTime.truncate(:second)
    pending = insert_issue!(repository, 1)
    _classified = insert_issue!(repository, 2, %{classified_at: classified_at})

    assert :ok = perform_job(GitHubIssueClassificationSweeper, %{})

    pending_id = pending.id

    assert [%Oban.Job{args: %{"issue_id" => ^pending_id}}] =
             all_enqueued(worker: GitHubIssueClassificationWorker)
  end

  test "perform/1 is a no-op when every issue has already been classified" do
    stub(Hive.Agents, :enabled?, fn -> true end)

    repository = create_repository!()
    classified_at = DateTime.utc_now() |> DateTime.truncate(:second)
    insert_issue!(repository, 1, %{classified_at: classified_at})

    assert :ok = perform_job(GitHubIssueClassificationSweeper, %{})
    assert [] = all_enqueued(worker: GitHubIssueClassificationWorker)
  end

  test "perform/1 does not retry terminal provider failures" do
    stub(Hive.Agents, :enabled?, fn -> true end)

    repository = create_repository!()
    issue = insert_issue!(repository, 1)

    GitHubIssueClassification.mark_failed(issue.id, :llm_invalid_credentials)

    assert :ok = perform_job(GitHubIssueClassificationSweeper, %{})
    assert [] = all_enqueued(worker: GitHubIssueClassificationWorker)
  end

  test "perform/1 leaves an account-scoped failure alone during its cooldown" do
    stub(Hive.Agents, :enabled?, fn -> true end)

    repository = create_repository!()
    issue = insert_issue!(repository, 1)

    GitHubIssueClassification.mark_failed(issue.id, :llm_credit_limit)

    assert :ok = perform_job(GitHubIssueClassificationSweeper, %{})
    assert [] = all_enqueued(worker: GitHubIssueClassificationWorker)
  end

  test "perform/1 reconsiders an account-scoped failure once the cooldown passes" do
    stub(Hive.Agents, :enabled?, fn -> true end)

    repository = create_repository!()
    issue = insert_issue!(repository, 1)

    GitHubIssueClassification.mark_failed(issue.id, :llm_credit_limit)
    backdate_failure!(issue.id, 7_200)

    assert :ok = perform_job(GitHubIssueClassificationSweeper, %{})

    issue_id = issue.id

    assert [%Oban.Job{args: %{"issue_id" => ^issue_id}}] =
             all_enqueued(worker: GitHubIssueClassificationWorker)
  end

  test "perform/1 never reconsiders a record-scoped failure" do
    stub(Hive.Agents, :enabled?, fn -> true end)

    repository = create_repository!()
    issue = insert_issue!(repository, 1)

    GitHubIssueClassification.mark_failed(issue.id, :llm_provider_rejected_request)
    backdate_failure!(issue.id, 7_200)

    assert :ok = perform_job(GitHubIssueClassificationSweeper, %{})
    assert [] = all_enqueued(worker: GitHubIssueClassificationWorker)
  end

  test "re-marking an account-scoped failure refreshes its cooldown" do
    stub(Hive.Agents, :enabled?, fn -> true end)

    repository = create_repository!()
    issue = insert_issue!(repository, 1)

    GitHubIssueClassification.mark_failed(issue.id, :llm_credit_limit)
    backdate_failure!(issue.id, 7_200)

    GitHubIssueClassification.mark_failed(issue.id, :llm_credit_limit)

    assert :ok = perform_job(GitHubIssueClassificationSweeper, %{})
    assert [] = all_enqueued(worker: GitHubIssueClassificationWorker)
  end

  defp backdate_failure!(issue_id, seconds_ago) do
    failed_at =
      DateTime.utc_now() |> DateTime.add(-seconds_ago, :second) |> DateTime.truncate(:second)

    Repo.update_all(
      from(issue in GitHubIssue, where: issue.id == ^issue_id),
      set: [classification_failed_at: failed_at]
    )
  end
end

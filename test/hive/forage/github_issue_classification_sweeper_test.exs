defmodule Hive.Forage.GitHubIssueClassificationSweeperTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueClassificationSweeper
  alias Hive.Forage.GitHubIssueClassificationWorker
  alias Hive.Domains

  defp unique, do: System.unique_integer([:positive])

  defp create_repository! do
    suffix = unique()

    {:ok, domain} =
      Domains.create_domain(%{
        name: "sweeper-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo#{suffix}",
        github_repository_visibility: "public"
      })

    hd(domain.project.github_repositories)
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
end

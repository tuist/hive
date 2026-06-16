defmodule Hive.Forage.GitHubIssueClassificationWorkerTest do
  use Hive.DataCase, async: true
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Forage.GitHubIssueClassificationWorker

  test "enqueue/2 inserts a unique classification job per issue when agents are enabled" do
    assert {:ok, %Oban.Job{} = first} =
             GitHubIssueClassificationWorker.enqueue("00000000-0000-0000-0000-000000000001",
               agents_enabled?: fn -> true end
             )

    assert {:ok, %Oban.Job{} = second} =
             GitHubIssueClassificationWorker.enqueue("00000000-0000-0000-0000-000000000001",
               agents_enabled?: fn -> true end
             )

    assert first.id == second.id
    assert second.conflict?
    assert first.queue == "agents"
    assert first.worker == inspect(GitHubIssueClassificationWorker)
    assert first.args == %{"issue_id" => "00000000-0000-0000-0000-000000000001"}
  end

  test "enqueue/2 skips when agentic workflows are dormant" do
    assert :skipped =
             GitHubIssueClassificationWorker.enqueue("00000000-0000-0000-0000-000000000001",
               agents_enabled?: fn -> false end
             )

    assert [] = all_enqueued(worker: GitHubIssueClassificationWorker)
  end

  test "perform/1 returns :ok when the issue no longer exists" do
    assert :ok =
             perform_job(GitHubIssueClassificationWorker, %{
               "issue_id" => "00000000-0000-0000-0000-000000000001"
             })
  end
end

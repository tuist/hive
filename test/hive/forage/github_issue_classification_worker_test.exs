defmodule Hive.Forage.GitHubIssueClassificationWorkerTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  import ExUnit.CaptureLog

  alias Hive.Domains
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueClassification
  alias Hive.Forage.GitHubIssueClassificationWorker
  alias Hive.Projects

  defp insert_issue! do
    suffix = System.unique_integer([:positive])
    {:ok, project} = Projects.create_project(%{name: "Project #{suffix}"})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Domain #{suffix}",
        project_id: project.id,
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo#{suffix}",
        github_repository_visibility: "public"
      })

    repository = github_repository_for_domain!(domain)

    Repo.insert!(
      GitHubIssue.changeset(%GitHubIssue{}, %{
        github_repository_id: repository.id,
        number: 1,
        title: "Issue",
        state: :open
      })
    )
  end

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

  test "perform/1 cancels hard provider availability errors" do
    issue = insert_issue!()

    error =
      ReqLLM.Error.API.Request.exception(
        reason:
          "Provider response error (412): Fireworks_ai API error: Account tuist is suspended, possibly due to reaching the monthly spending limit or failure to pay past invoices.",
        status: 412,
        response_body: "412 Provider error",
        request_body: "full prompt body"
      )

    expect(GitHubIssueClassification, :classify, fn id when id == issue.id -> {:error, error} end)

    log =
      capture_log(fn ->
        assert {:cancel, :llm_provider_unavailable} =
                 GitHubIssueClassificationWorker.perform(%Oban.Job{
                   args: %{"issue_id" => issue.id}
                 })
      end)

    assert log =~ "Model provider rejected"
    refute log =~ "full prompt body"

    failed = Repo.get!(GitHubIssue, issue.id)
    assert failed.classification_failure == "llm_provider_unavailable"
    assert %DateTime{} = failed.classification_failed_at
  end

  test "perform/1 catches and snoozes raised rate-limit errors" do
    error =
      ReqLLM.Error.API.Request.exception(
        reason:
          "Provider response error (429): Fireworks_ai API error: Too many requests due to rate limit.",
        status: 429,
        response_body: "429 Provider error",
        request_body: "full prompt body"
      )

    expect(GitHubIssueClassification, :classify, fn "issue-id" -> raise error end)

    assert {:snooze, 3_600} =
             GitHubIssueClassificationWorker.perform(%Oban.Job{
               args: %{"issue_id" => "issue-id"}
             })
  end

  test "perform/1 sanitizes unexpected provider request errors before returning them to Oban" do
    error =
      ReqLLM.Error.API.Request.exception(
        reason: "Provider response error (500): Openai API error",
        status: 500,
        response_body: "500 Internal Server Error",
        request_body: "full prompt body"
      )

    expect(GitHubIssueClassification, :classify, fn "issue-id" -> {:error, error} end)

    result =
      GitHubIssueClassificationWorker.perform(%Oban.Job{
        args: %{"issue_id" => "issue-id"}
      })

    assert {:error, {:llm_request_failed, 500, message}} = result
    assert message == "API request failed (500): Provider response error (500): Openai API error"
    refute inspect(result) =~ "full prompt body"
  end
end

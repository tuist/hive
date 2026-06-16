defmodule Hive.Specs.RevisionSummaryWorkerTest do
  use Hive.DataCase, async: true
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Accounts
  alias Hive.Specs
  alias Hive.Specs.RevisionSummaryWorker

  defp user(email \\ "alice@example.com") do
    {:ok, user} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    user
  end

  test "enqueue/2 inserts a unique summary job per revision when agents are enabled" do
    assert {:ok, %Oban.Job{} = first} =
             RevisionSummaryWorker.enqueue("00000000-0000-0000-0000-000000000001",
               agents_enabled?: fn -> true end
             )

    assert {:ok, %Oban.Job{} = second} =
             RevisionSummaryWorker.enqueue("00000000-0000-0000-0000-000000000001",
               agents_enabled?: fn -> true end
             )

    assert first.id == second.id
    assert second.conflict?
    assert first.queue == "agents"
    assert first.worker == inspect(RevisionSummaryWorker)
    assert first.args == %{"revision_id" => "00000000-0000-0000-0000-000000000001"}
  end

  test "enqueue/2 skips when agentic workflows are dormant" do
    assert :skipped =
             RevisionSummaryWorker.enqueue("00000000-0000-0000-0000-000000000001",
               agents_enabled?: fn -> false end
             )

    assert [] = all_enqueued(worker: RevisionSummaryWorker)
  end

  test "perform/1 returns :ok when the revision no longer exists" do
    assert :ok =
             perform_job(RevisionSummaryWorker, %{
               "revision_id" => "00000000-0000-0000-0000-000000000001"
             })
  end

  test "perform/1 is a no-op for the very first revision" do
    user = user()

    {:ok, spec} = Specs.create_spec(%{"title" => "A spec", "body" => "Initial body."}, user)
    spec = Specs.get_spec!(spec.id)
    [first] = spec.revisions

    assert :ok = perform_job(RevisionSummaryWorker, %{"revision_id" => first.id})

    refreshed = Specs.get_spec!(spec.id)
    refute Enum.any?(refreshed.revisions, & &1.summary)
  end
end

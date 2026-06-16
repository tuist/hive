defmodule Hive.Meadows.EvolutionWorkerTest do
  use Hive.DataCase, async: true
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Meadows.EvolutionWorker

  test "enqueue/1 inserts a delayed unique evolution job when agents are enabled" do
    assert {:ok, %Oban.Job{} = first_job} =
             EvolutionWorker.enqueue(agents_enabled?: fn -> true end)

    assert {:ok, %Oban.Job{} = second_job} =
             EvolutionWorker.enqueue(agents_enabled?: fn -> true end)

    assert first_job.id == second_job.id
    assert second_job.conflict?
    assert first_job.queue == "meadows"
    assert first_job.worker == inspect(EvolutionWorker)
    assert DateTime.compare(first_job.scheduled_at, DateTime.utc_now()) == :gt

    assert [%Oban.Job{}] = all_enqueued(worker: EvolutionWorker, queue: "meadows")
  end

  test "enqueue/1 skips when agentic workflows are dormant" do
    assert :skipped = EvolutionWorker.enqueue(agents_enabled?: fn -> false end)
    assert [] = all_enqueued(worker: EvolutionWorker)
  end

  test "perform/1 evolves from work items" do
    assert :ok = perform_job(EvolutionWorker, %{})
  end
end

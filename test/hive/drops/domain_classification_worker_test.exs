defmodule Hive.Drops.DomainClassificationWorkerTest do
  use Hive.DataCase, async: true
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Drops.DomainClassificationWorker

  test "enqueue/2 inserts a unique classification job per drop" do
    assert {:ok, %Oban.Job{} = first} =
             DomainClassificationWorker.enqueue("00000000-0000-0000-0000-000000000001")

    assert {:ok, %Oban.Job{} = second} =
             DomainClassificationWorker.enqueue("00000000-0000-0000-0000-000000000001")

    assert first.id == second.id
    assert second.conflict?
    assert first.queue == "agents"
    assert first.worker == inspect(DomainClassificationWorker)
    assert first.args == %{"drop_id" => "00000000-0000-0000-0000-000000000001"}
  end

  test "enqueue/2 skips when an explicit agents_enabled callback returns false" do
    assert :skipped =
             DomainClassificationWorker.enqueue("00000000-0000-0000-0000-000000000001",
               agents_enabled?: fn -> false end
             )

    assert [] = all_enqueued(worker: DomainClassificationWorker)
  end
end

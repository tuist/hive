defmodule Hive.Drops.DomainClassificationSweeperTest do
  use Hive.DataCase, async: true
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Drops
  alias Hive.Drops.DomainClassificationSweeper
  alias Hive.Drops.DomainClassificationWorker

  defp insert_drop!(suffix) do
    {:ok, drop} =
      Drops.upsert_drop(%{
        source_type: :rss,
        external_id: "sweeper-#{suffix}",
        title: "Drop #{suffix}",
        url: "https://example.com/drops/#{suffix}"
      })

    drop
  end

  test "enqueues pending drops but not completed or terminally failed drops" do
    pending = insert_drop!("pending")
    completed = insert_drop!("completed")
    failed = insert_drop!("failed")

    Drops.replace_drop_domains(completed, [])
    Drops.mark_drop_classification_failed(failed.id, :llm_invalid_credentials)

    assert :ok = perform_job(DomainClassificationSweeper, %{})

    pending_id = pending.id

    assert [%Oban.Job{args: %{"drop_id" => ^pending_id}}] =
             all_enqueued(worker: DomainClassificationWorker)
  end

  test "deduplicates overlapping scheduled sweeps" do
    assert {:ok, first} = DomainClassificationSweeper.new(%{}) |> Oban.insert()
    assert {:ok, second} = DomainClassificationSweeper.new(%{}) |> Oban.insert()

    assert first.id == second.id
    assert second.conflict?
  end
end

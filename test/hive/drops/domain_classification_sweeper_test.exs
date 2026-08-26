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

  test "perform/1 leaves an account-scoped failure alone during its cooldown" do
    drop = insert_drop!(System.unique_integer([:positive]))
    :ok = Drops.mark_drop_classification_failed(drop.id, :llm_credit_limit)

    assert :ok = perform_job(DomainClassificationSweeper, %{})
    assert [] = all_enqueued(worker: DomainClassificationWorker)
  end

  test "perform/1 reconsiders an account-scoped failure once the cooldown passes" do
    drop = insert_drop!(System.unique_integer([:positive]))
    :ok = Drops.mark_drop_classification_failed(drop.id, :llm_credit_limit)
    backdate_failure!(drop.id, 7_200)

    assert :ok = perform_job(DomainClassificationSweeper, %{})

    drop_id = drop.id

    assert [%Oban.Job{args: %{"drop_id" => ^drop_id}}] =
             all_enqueued(worker: DomainClassificationWorker)
  end

  test "perform/1 never reconsiders a record-scoped failure" do
    drop = insert_drop!(System.unique_integer([:positive]))
    :ok = Drops.mark_drop_classification_failed(drop.id, :llm_invalid_credentials)
    backdate_failure!(drop.id, 7_200)

    assert :ok = perform_job(DomainClassificationSweeper, %{})
    assert [] = all_enqueued(worker: DomainClassificationWorker)
  end

  defp backdate_failure!(drop_id, seconds_ago) do
    failed_at =
      DateTime.utc_now() |> DateTime.add(-seconds_ago, :second) |> DateTime.truncate(:second)

    Repo.update_all(
      from(drop in Hive.Drops.Drop, where: drop.id == ^drop_id),
      set: [classification_failed_at: failed_at]
    )
  end
end

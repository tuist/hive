defmodule Hive.Drops.WeeklyDigestWorkerTest do
  use Hive.DataCase, async: true

  import Mimic

  alias Hive.Audit.Activity
  alias Hive.Drops.WeeklyDigest
  alias Hive.Drops.WeeklyDigests
  alias Hive.Drops.WeeklyDigestWorker

  test "records a newly published weekly edition once" do
    digest = %WeeklyDigest{
      id: Ecto.UUID.generate(),
      week_start: ~D[2026-07-06],
      week_end: ~D[2026-07-10],
      title: "The connected week"
    }

    stub(WeeklyDigests, :generate_latest_week, fn -> {:ok, digest, :published} end)

    assert :ok = WeeklyDigestWorker.perform(%Oban.Job{})

    assert %Activity{
             action: "drop.weekly_digest.generated",
             interface: "worker",
             target_type: "drop_digest",
             target_label: "The connected week"
           } = Repo.get_by!(Activity, target_id: digest.id)
  end

  test "does not audit an edition that already existed" do
    digest = %WeeklyDigest{id: Ecto.UUID.generate()}
    stub(WeeklyDigests, :generate_latest_week, fn -> {:ok, digest, :existing} end)

    assert :ok = WeeklyDigestWorker.perform(%Oban.Job{})
    refute Repo.get_by(Activity, target_id: digest.id)
  end

  test "snoozes while another worker owns the weekly claim" do
    digest = %WeeklyDigest{id: Ecto.UUID.generate()}
    stub(WeeklyDigests, :generate_latest_week, fn -> {:ok, digest, :busy} end)

    assert {:snooze, 300} = WeeklyDigestWorker.perform(%Oban.Job{})
  end

  test "cancels credit-limit failures instead of retrying" do
    stub(WeeklyDigests, :generate_latest_week, fn -> {:error, :llm_credit_limit} end)

    assert {:cancel, :llm_credit_limit} = WeeklyDigestWorker.perform(%Oban.Job{})
  end
end

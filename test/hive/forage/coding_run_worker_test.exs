defmodule Hive.Forage.CodingRunWorkerTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Forage.CodingRunWorker
  alias Hive.Forage.CodingRuns

  test "executes the durable coding run once" do
    run_id = Ecto.UUID.generate()
    expect(CodingRuns, :execute, fn ^run_id -> :ok end)

    assert :ok = perform_job(CodingRunWorker, %{"coding_run_id" => run_id})
  end
end

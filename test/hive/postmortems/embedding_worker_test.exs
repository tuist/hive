defmodule Hive.Postmortems.EmbeddingWorkerTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Postmortems
  alias Hive.Postmortems.EmbeddingWorker

  test "tombstones the record with :llm_transient_exhausted on the final attempt" do
    expect(Postmortems, :index_postmortem, fn "postmortem-id", "content-hash" ->
      {:error, :timeout}
    end)

    expect(Postmortems, :mark_embedding_failed, fn
      "postmortem-id", "content-hash", "llm_transient_exhausted" -> :ok
    end)

    assert {:discard, :llm_transient_exhausted} =
             EmbeddingWorker.perform(%Oban.Job{
               args: %{
                 "postmortem_id" => "postmortem-id",
                 "content_hash" => "content-hash"
               },
               attempt: 3,
               max_attempts: 3
             })
  end

  test "snoozes provider-unavailable failures while attempts remain" do
    expect(Postmortems, :index_postmortem, fn "postmortem-id", "content-hash" ->
      {:error, :timeout}
    end)

    reject(&Postmortems.mark_embedding_failed/3)

    assert {:snooze, 3_600} =
             EmbeddingWorker.perform(%Oban.Job{
               args: %{
                 "postmortem_id" => "postmortem-id",
                 "content_hash" => "content-hash"
               },
               attempt: 2,
               max_attempts: 3
             })
  end
end

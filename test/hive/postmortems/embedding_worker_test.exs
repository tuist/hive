defmodule Hive.Postmortems.EmbeddingWorkerTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Postmortems
  alias Hive.Postmortems.EmbeddingWorker

  test "records a durable failure after the final transient attempt" do
    expect(Postmortems, :index_postmortem, fn "postmortem-id", "content-hash" ->
      {:error, :timeout}
    end)

    expect(Postmortems, :mark_embedding_failed, fn
      "postmortem-id", "content-hash", ":timeout" -> :ok
    end)

    assert {:error, :timeout} =
             EmbeddingWorker.perform(%Oban.Job{
               args: %{
                 "postmortem_id" => "postmortem-id",
                 "content_hash" => "content-hash"
               },
               attempt: 3,
               max_attempts: 3
             })
  end

  test "keeps transient failures pending while attempts remain" do
    expect(Postmortems, :index_postmortem, fn "postmortem-id", "content-hash" ->
      {:error, :timeout}
    end)

    reject(&Postmortems.mark_embedding_failed/3)

    assert {:error, :timeout} =
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

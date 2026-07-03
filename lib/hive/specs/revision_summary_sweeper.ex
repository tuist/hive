defmodule Hive.Specs.RevisionSummarySweeper do
  @moduledoc """
  Periodic Oban job that enqueues summary generation for spec revisions
  whose agent-written summary is still missing.

  Runs on the `:agents` queue. Each backfill is delegated to
  `RevisionSummaryWorker` so failures and retries stay scoped to a
  single revision.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue], period: :infinity, states: :incomplete]

  import Ecto.Query

  require Logger

  alias Hive.Repo
  alias Hive.Specs.Revision
  alias Hive.Specs.RevisionSummaryWorker

  @batch_size 200

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    ids =
      Revision
      |> where([revision], revision.revision > 1)
      |> where([revision], is_nil(revision.summary) or revision.summary == "")
      |> order_by([revision], asc: revision.inserted_at)
      |> limit(^@batch_size)
      |> select([revision], revision.id)
      |> Repo.all()

    Enum.each(ids, &RevisionSummaryWorker.enqueue/1)

    Logger.debug("[Specs.RevisionSummarySweeper] Enqueued #{length(ids)} missing summaries")

    :ok
  end
end

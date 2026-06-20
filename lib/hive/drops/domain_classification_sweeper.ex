defmodule Hive.Drops.DomainClassificationSweeper do
  @moduledoc """
  Re-enqueues classification for any drop still missing a
  `classified_at`. Catches drops created before classification shipped,
  or drops whose classification hit a transient LLM error. Runs on a
  fixed schedule from `Oban.Plugins.Cron`.
  """

  use Oban.Worker, queue: :agents, max_attempts: 1

  alias Hive.Drops
  alias Hive.Drops.DomainClassificationWorker

  @batch_size 50

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Drops.list_unclassified_drops(limit: @batch_size)
    |> Enum.each(fn drop -> DomainClassificationWorker.enqueue(drop.id) end)

    :ok
  end
end

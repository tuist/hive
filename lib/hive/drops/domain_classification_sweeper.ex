defmodule Hive.Drops.DomainClassificationSweeper do
  @moduledoc """
  Re-enqueues pending drop classifications. Catches drops created before
  classification shipped or whose classification hit a transient model
  error. Terminal provider failures are persisted and excluded. Runs on
  a fixed schedule from `Oban.Plugins.Cron`.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue], period: :infinity, states: :incomplete]

  require Logger

  alias Hive.Drops
  alias Hive.Drops.DomainClassificationWorker

  @batch_size 50

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    drops = Drops.list_unclassified_drops(limit: @batch_size)

    Enum.each(drops, fn drop -> DomainClassificationWorker.enqueue(drop.id) end)

    Logger.debug("[Drops.DomainClassificationSweeper] Enqueued #{length(drops)} pending drops")

    :ok
  end
end

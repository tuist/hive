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

  alias Hive.Agents.Errors
  alias Hive.Drops
  alias Hive.Drops.DomainClassificationWorker

  @batch_size 50

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    drops =
      [limit: @batch_size]
      |> Drops.list_unclassified_drops()
      |> Enum.filter(&past_reason_cooldown?(&1, now))

    Enum.each(drops, fn drop -> DomainClassificationWorker.enqueue(drop.id) end)

    Logger.debug("[Drops.DomainClassificationSweeper] Enqueued #{length(drops)} pending drops")

    :ok
  end

  defp past_reason_cooldown?(%{classification_failed_at: nil}, _now), do: true
  defp past_reason_cooldown?(%{classification_failure: nil}, _now), do: true

  defp past_reason_cooldown?(
         %{classification_failure: reason, classification_failed_at: failed_at},
         now
       ) do
    case Errors.reconsideration_cooldown(reason) do
      nil -> false
      cooldown -> DateTime.compare(failed_at, DateTime.add(now, -cooldown, :second)) == :lt
    end
  end
end

defmodule Hive.Drops.DomainClassificationWorker do
  @moduledoc """
  Runs the drop-to-domain classifier asynchronously so the syncer can
  return without waiting for the model call. Jobs are de-duplicated per
  drop while they sit in the queue.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  alias Hive.Drops.DomainClassification

  @doc """
  Enqueues a classification job for the given drop id. Returns
  `:skipped` when an explicit `agents_enabled?: false` callback is
  passed so callers can short-circuit without scheduling work. The
  worker itself runs both the model-enabled and the fallback paths.
  """
  def enqueue(drop_id, opts \\ []) when is_binary(drop_id) do
    if Keyword.has_key?(opts, :agents_enabled?) and
         not Keyword.fetch!(opts, :agents_enabled?).() do
      :skipped
    else
      %{"drop_id" => drop_id}
      |> new()
      |> Oban.insert()
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"drop_id" => drop_id}}), do: classify(drop_id)

  defp classify(drop_id) do
    case DomainClassification.classify(drop_id) do
      {:ok, _domain_ids} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

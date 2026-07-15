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

  require Logger

  alias Hive.Agents.Errors
  alias Hive.Drops
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
  def perform(%Oban.Job{args: %{"drop_id" => drop_id}}) do
    drop_id
    |> DomainClassification.classify()
    |> handle_classification_result(drop_id)
  rescue
    error in [ReqLLM.Error.API.Request, ReqLLM.Error.API.Response] ->
      handle_classification_result({:error, error}, drop_id)
  end

  defp handle_classification_result(result, drop_id) do
    case result do
      {:ok, _domain_ids} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> handle_classification_error(drop_id, reason)
    end
  end

  defp handle_classification_error(drop_id, reason) do
    sanitized_reason = Errors.sanitize_reason(reason, :drop_domain_classification_failed)

    case Errors.hard_failure_reason(reason) do
      nil ->
        Logger.warning(
          "[Drops.DomainClassificationWorker] Classification failed for drop #{drop_id}: #{inspect(sanitized_reason)}"
        )

        {:error, sanitized_reason}

      hard_reason ->
        :ok = Drops.mark_drop_classification_failed(drop_id, hard_reason)

        Logger.warning(
          "[Drops.DomainClassificationWorker] Model provider rejected classification for drop #{drop_id}: #{inspect(sanitized_reason)}"
        )

        {:cancel, hard_reason}
    end
  end
end

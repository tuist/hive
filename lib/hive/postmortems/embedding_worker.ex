defmodule Hive.Postmortems.EmbeddingWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  alias Hive.Agents.Errors
  alias Hive.Postmortems

  @embedding_unavailable_snooze_seconds 3_600

  def enqueue(postmortem_id, content_hash) do
    %{"postmortem_id" => postmortem_id, "content_hash" => content_hash}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"postmortem_id" => id, "content_hash" => content_hash}} = job) do
    case Postmortems.index_postmortem(id, content_hash) do
      {:ok, _embedding} -> :ok
      {:error, :not_found} -> :ok
      {:error, :embedding_not_configured} -> {:snooze, @embedding_unavailable_snooze_seconds}
      {:error, reason} -> handle_error(job, id, content_hash, reason)
    end
  rescue
    error in [ReqLLM.Error.API.Request, ReqLLM.Error.API.Response] ->
      handle_error(job, id, content_hash, error)
  end

  defp handle_error(job, id, content_hash, reason) do
    cond do
      hard_reason = Errors.hard_failure_reason(reason) ->
        :ok = Postmortems.mark_embedding_failed(id, content_hash, hard_reason)
        {:cancel, hard_reason}

      Errors.terminal_attempt?(job) ->
        :ok =
          Postmortems.mark_embedding_failed(id, content_hash, "llm_transient_exhausted")

        {:discard, :llm_transient_exhausted}

      Errors.provider_unavailable?(reason) ->
        {:snooze, @embedding_unavailable_snooze_seconds}

      true ->
        {:error, Errors.sanitize_reason(reason, :postmortem_embedding_failed)}
    end
  end
end

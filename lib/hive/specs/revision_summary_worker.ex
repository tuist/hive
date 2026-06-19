defmodule Hive.Specs.RevisionSummaryWorker do
  @moduledoc """
  Generates the agent-written summary for a spec revision asynchronously
  so the request that created the revision returns immediately.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  require Logger

  alias Hive.Specs.RevisionSummaries

  @doc """
  Enqueues a summary job for the given revision id. Returns `:skipped`
  when agentic workflows are dormant.
  """
  def enqueue(revision_id, opts \\ []) when is_binary(revision_id) do
    agents_enabled? = Keyword.get(opts, :agents_enabled?, &Hive.Agents.enabled?/0)

    if agents_enabled?.() do
      %{"revision_id" => revision_id}
      |> new()
      |> Oban.insert()
    else
      :skipped
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"revision_id" => revision_id}}) do
    case RevisionSummaries.summarize(revision_id) do
      {:ok, _revision} ->
        :ok

      :skipped ->
        :ok

      {:error, :not_found} ->
        Logger.info("[Specs.RevisionSummaryWorker] Revision #{revision_id} no longer exists")
        :ok

      {:error, reason} ->
        sanitized_reason = sanitize_error_reason(reason)

        Logger.warning(
          "[Specs.RevisionSummaryWorker] Summary generation failed for revision #{revision_id}: #{inspect(sanitized_reason)}"
        )

        {:error, sanitized_reason}
    end
  end

  defp sanitize_error_reason(%ReqLLM.Error.API.Request{} = error) do
    {:llm_request_failed, error.status, truncate_message(Exception.message(error))}
  end

  defp sanitize_error_reason(%ReqLLM.Error.API.Response{} = error) do
    {:llm_response_failed, error.status, truncate_message(Exception.message(error))}
  end

  defp sanitize_error_reason({:fallback_failed, reason, fallback_reason}) do
    {:fallback_failed, sanitize_error_reason(reason), sanitize_error_reason(fallback_reason)}
  end

  defp sanitize_error_reason({tag, reason}) when is_atom(tag) do
    {tag, sanitize_error_reason(reason)}
  end

  defp sanitize_error_reason(reason) when is_atom(reason), do: reason

  defp sanitize_error_reason(reason) when is_binary(reason) do
    truncate_message(reason)
  end

  defp sanitize_error_reason(%{__struct__: module}) when is_atom(module) do
    {:error, module}
  end

  defp sanitize_error_reason(reason) when is_tuple(reason) and tuple_size(reason) > 0 do
    {:error, elem(reason, 0)}
  end

  defp sanitize_error_reason(_reason), do: :revision_summary_failed

  defp truncate_message(message) do
    message
    |> String.trim()
    |> String.slice(0, 300)
  end
end

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

  alias Hive.Agents.Errors
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
        sanitized_reason = Errors.sanitize_reason(reason, :revision_summary_failed)

        Logger.warning(
          "[Specs.RevisionSummaryWorker] Summary generation failed for revision #{revision_id}: #{inspect(sanitized_reason)}"
        )

        {:error, sanitized_reason}
    end
  end
end

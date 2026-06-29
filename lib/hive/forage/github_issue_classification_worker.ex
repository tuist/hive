defmodule Hive.Forage.GitHubIssueClassificationWorker do
  @moduledoc """
  Runs the GitHub issue domain classifier asynchronously so the syncer can
  return without waiting for the LLM. Jobs are de-duplicated per issue
  while they sit in the queue.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  require Logger

  alias Hive.Agents.Errors
  alias Hive.Forage.GitHubIssueClassification

  @model_provider_unavailable_snooze_seconds 3_600

  @doc """
  Enqueues a classification job for the given issue id. Returns
  `:skipped` when agentic workflows are dormant; the syncer falls back to
  linking every candidate domain in that case.
  """
  def enqueue(issue_id, opts \\ []) when is_binary(issue_id) do
    agents_enabled? = Keyword.get(opts, :agents_enabled?, &Hive.Agents.enabled?/0)

    if agents_enabled?.() do
      %{"issue_id" => issue_id}
      |> new()
      |> Oban.insert()
    else
      :skipped
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"issue_id" => issue_id}}) do
    issue_id
    |> GitHubIssueClassification.classify()
    |> handle_classification_result(issue_id)
  rescue
    error in [ReqLLM.Error.API.Request, ReqLLM.Error.API.Response] ->
      handle_classification_result({:error, error}, issue_id)
  end

  defp handle_classification_result(result, issue_id) do
    case result do
      {:ok, _domain_ids} ->
        Hive.Domains.schedule_evolution()
        :ok

      {:error, :not_found} ->
        Logger.info("[Forage.GitHubIssueClassificationWorker] Issue #{issue_id} no longer exists")

        :ok

      {:error, reason} ->
        handle_classification_error(issue_id, reason)
    end
  end

  defp handle_classification_error(issue_id, reason) do
    sanitized_reason = Errors.sanitize_reason(reason)

    if Errors.provider_unavailable?(reason) do
      Logger.warning(
        "[Forage.GitHubIssueClassificationWorker] Model provider unavailable while classifying issue #{issue_id}: #{inspect(sanitized_reason)}"
      )

      {:snooze, @model_provider_unavailable_snooze_seconds}
    else
      Logger.warning(
        "[Forage.GitHubIssueClassificationWorker] Classification failed for issue #{issue_id}: #{inspect(sanitized_reason)}"
      )

      {:error, sanitized_reason}
    end
  end
end

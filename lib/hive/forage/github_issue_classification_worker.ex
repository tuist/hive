defmodule Hive.Forage.GitHubIssueClassificationWorker do
  @moduledoc """
  Runs the GitHub issue meadow classifier asynchronously so the syncer can
  return without waiting for the LLM. Jobs are de-duplicated per issue
  while they sit in the queue.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  require Logger

  alias Hive.Forage.GitHubIssueClassification

  @doc """
  Enqueues a classification job for the given issue id. Returns
  `:skipped` when agentic workflows are dormant; the syncer falls back to
  linking every candidate meadow in that case.
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
    case GitHubIssueClassification.classify(issue_id) do
      {:ok, _meadow_ids} ->
        :ok

      {:error, :not_found} ->
        Logger.info("[Forage.GitHubIssueClassificationWorker] Issue #{issue_id} no longer exists")

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end

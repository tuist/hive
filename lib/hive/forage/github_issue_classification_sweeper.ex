defmodule Hive.Forage.GitHubIssueClassificationSweeper do
  @moduledoc """
  Periodic Oban job that enqueues every pending GitHub issue
  classification. Catches rows that existed before the classifier shipped,
  rows whose classification job hit max attempts, and rows whose repository
  was attached to its first domain after the issue was already cached.
  Record-scoped provider failures are persisted and excluded; reconsiderable
  ones (credit exhaustion, provider outage, retry exhausted) are reconsidered
  after a per-reason cooldown so a short outage does not stay tombstoned
  behind a longer retry-exhaustion cooldown.

  Runs on the `:agents` queue. The sync-time backfill in
  `Hive.Forage.reconcile_repository_github_issues/2` covers the same
  ground when agentic workflows are dormant.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue], period: :infinity, states: :incomplete]

  import Ecto.Query

  require Logger

  alias Hive.Agents.Errors
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueClassificationWorker
  alias Hive.Repo

  @batch_size 200

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    sql_cutoff = DateTime.add(now, -Errors.shortest_reconsideration_cooldown(), :second)
    reconsiderable = Errors.reconsiderable_reason_names()

    candidates =
      GitHubIssue
      |> where(
        [issue],
        is_nil(issue.classified_at) and
          (is_nil(issue.classification_failed_at) or
             (issue.classification_failure in ^reconsiderable and
                issue.classification_failed_at < ^sql_cutoff))
      )
      |> order_by([issue], asc: issue.inserted_at)
      |> limit(^@batch_size)
      |> select([issue], {issue.id, issue.classification_failure, issue.classification_failed_at})
      |> Repo.all()

    ids =
      candidates
      |> Enum.filter(&past_reason_cooldown?(&1, now))
      |> Enum.map(&elem(&1, 0))

    Enum.each(ids, &GitHubIssueClassificationWorker.enqueue/1)

    Logger.debug(
      "[Forage.GitHubIssueClassificationSweeper] Enqueued #{length(ids)} unclassified issues"
    )

    :ok
  end

  defp past_reason_cooldown?({_id, nil, _failed_at}, _now), do: true
  defp past_reason_cooldown?({_id, _reason, nil}, _now), do: true

  defp past_reason_cooldown?({_id, reason, failed_at}, now) do
    case Errors.reconsideration_cooldown(reason) do
      nil -> false
      cooldown -> DateTime.compare(failed_at, DateTime.add(now, -cooldown, :second)) == :lt
    end
  end
end

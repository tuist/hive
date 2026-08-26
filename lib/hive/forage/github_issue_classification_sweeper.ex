defmodule Hive.Forage.GitHubIssueClassificationSweeper do
  @moduledoc """
  Periodic Oban job that enqueues every pending GitHub issue
  classification. Catches rows that existed before the classifier shipped,
  rows whose classification job hit max attempts, and rows whose repository
  was attached to its first domain after the issue was already cached.
  Record-scoped provider failures are persisted and excluded; account-scoped
  ones such as credit exhaustion are reconsidered after a cooldown, since they
  said nothing about the issue that happened to be in flight.

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

  # How long an issue tombstoned by an account-scoped model failure waits before
  # this sweeper reconsiders it.
  @account_failure_retry_after 3_600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@account_failure_retry_after, :second)
      |> DateTime.truncate(:second)

    account_failures = Errors.account_failure_names()

    ids =
      GitHubIssue
      |> where(
        [issue],
        is_nil(issue.classified_at) and
          (is_nil(issue.classification_failed_at) or
             (issue.classification_failure in ^account_failures and
                issue.classification_failed_at < ^cutoff))
      )
      |> order_by([issue], asc: issue.inserted_at)
      |> limit(^@batch_size)
      |> select([issue], issue.id)
      |> Repo.all()

    Enum.each(ids, &GitHubIssueClassificationWorker.enqueue/1)

    Logger.debug(
      "[Forage.GitHubIssueClassificationSweeper] Enqueued #{length(ids)} unclassified issues"
    )

    :ok
  end
end

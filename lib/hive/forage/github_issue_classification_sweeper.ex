defmodule Hive.Forage.GitHubIssueClassificationSweeper do
  @moduledoc """
  Periodic Oban job that enqueues classification for every GitHub issue
  whose `classified_at` is `nil`. Catches rows that existed before the
  classifier shipped, rows whose classification job hit max attempts, and
  rows whose repository was attached to its first meadow after the issue
  was already cached.

  Runs on the `:agents` queue, which only boots when an LLM is
  configured. The sync-time backfill in
  `Hive.Forage.reconcile_repository_github_issues/2` covers the same
  ground when no LLM is available.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue], period: :infinity, states: :incomplete]

  import Ecto.Query

  require Logger

  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueClassificationWorker
  alias Hive.Repo

  @batch_size 200

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    ids =
      GitHubIssue
      |> where([issue], is_nil(issue.classified_at))
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

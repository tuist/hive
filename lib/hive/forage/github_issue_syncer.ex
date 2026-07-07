defmodule Hive.Forage.GitHubIssueSyncer do
  @moduledoc """
  Oban worker that reconciles the `forage_github_issues` cache with GitHub.
  Scheduled runs fan out into one repository job per repository so the cron
  check-in stays small and repository work cannot block the next heartbeat.

  The worker is scheduled from Oban's cron configuration. If the GitHub
  App is not configured it logs and skips, which is useful in development
  where seeds populate the cache by hand.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  @behaviour Sentry.Integrations.Oban.Cron

  require Logger

  alias Hive.Forage
  alias Hive.Domains.GitHubRepository
  alias Hive.GitHub.Client
  alias Hive.GitHub.Issues
  alias Hive.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"repository_id" => repository_id}}) do
    sync_repository_by_id(repository_id)
  end

  def perform(%Oban.Job{}) do
    enqueue_all_repositories()
  end

  @impl Sentry.Integrations.Oban.Cron
  def sentry_check_in_configuration(%Oban.Job{}) do
    [monitor_config: [checkin_margin: 5, max_runtime: 5]]
  end

  def enqueue_repository(%GitHubRepository{id: repository_id}) do
    %{"repository_id" => repository_id}
    |> new()
    |> Oban.insert()
  end

  defp sync_repository_by_id(repository_id) do
    with {:ok, repository_id} <- Ecto.UUID.cast(repository_id),
         %GitHubRepository{} = repository <- Repo.get(GitHubRepository, repository_id) do
      case Client.config() do
        {:ok, _config} ->
          sync_repository(repository)

        {:error, {:not_configured, _missing}} ->
          Logger.debug("[GitHubIssueSyncer] GitHub App not configured; skipping sync")
          :ok
      end
    else
      _unknown_repository ->
        :ok
    end
  end

  defp enqueue_all_repositories do
    case Client.config() do
      {:ok, _config} ->
        repositories = Forage.list_github_issue_repositories()

        Enum.each(repositories, &enqueue_repository_sync/1)

        Logger.debug("[GitHubIssueSyncer] Enqueued #{length(repositories)} repository syncs")
        :ok

      {:error, {:not_configured, _missing}} ->
        Logger.debug("[GitHubIssueSyncer] GitHub App not configured; skipping sync")
        :ok
    end
  end

  defp enqueue_repository_sync(repository) do
    case enqueue_repository(repository) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[GitHubIssueSyncer] Failed to enqueue #{repository.owner}/#{repository.name}: " <>
            inspect(reason)
        )
    end
  end

  @doc "Runs the GitHub issue sync immediately and returns when it finishes."
  def sync_now do
    case Client.config() do
      {:ok, _config} ->
        Forage.list_github_issue_repositories()
        |> Enum.each(&sync_repository/1)

        :ok

      {:error, {:not_configured, _missing}} ->
        Logger.debug("[GitHubIssueSyncer] GitHub App not configured; skipping sync")
        :skipped
    end
  end

  defp sync_repository(%GitHubRepository{} = repository) do
    case Issues.list_open_issues(repository) do
      {:ok, issues} ->
        entries =
          Enum.map(issues, fn issue ->
            %{number: issue.number, title: issue.title, body: issue.body}
          end)

        Forage.reconcile_repository_github_issues(repository, entries)

      {:error, reason} ->
        Logger.warning(
          "[GitHubIssueSyncer] Failed to sync #{repository.owner}/#{repository.name}: " <>
            inspect(reason)
        )
    end
  end
end

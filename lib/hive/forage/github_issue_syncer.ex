defmodule Hive.Forage.GitHubIssueSyncer do
  @moduledoc """
  Oban worker that reconciles the `forage_github_issues` cache with
  GitHub. Iterates every repository connected to a domain, pulls its open
  issues via the configured GitHub App installation, and updates the table
  so the dashboard renders without per-request API calls.

  The worker is scheduled from Oban's cron configuration. If the GitHub
  App is not configured it logs and skips, which is useful in development
  where seeds populate the cache by hand.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [fields: [:worker, :queue, :args], period: 60, states: :incomplete]

  require Logger

  alias Hive.Forage
  alias Hive.Domains.GitHubRepository
  alias Hive.GitHub.Client
  alias Hive.GitHub.Issues

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case sync_now() do
      :skipped -> :ok
      result -> result
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

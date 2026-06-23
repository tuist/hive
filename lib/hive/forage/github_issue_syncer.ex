defmodule Hive.Forage.GitHubIssueSyncer do
  @moduledoc """
  Periodically reconciles the `forage_github_issues` cache with GitHub.
  Iterates every repository connected to a domain, pulls its open issues
  via the configured GitHub App installation, and updates the table so
  the dashboard renders without per-request API calls.

  The syncer ticks on startup and then every `:interval_ms` (default 15
  minutes). If the GitHub App is not configured the syncer keeps running
  but logs and skips — useful in dev where seeds populate the cache by
  hand.
  """

  use GenServer

  require Logger

  alias Hive.Forage
  alias Hive.GitHub.Client
  alias Hive.GitHub.Issues
  alias Hive.Domains.GitHubRepository

  @default_interval_ms :timer.minutes(15)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc "Trigger a sync immediately. Returns once the run finishes."
  def sync_now(server \\ __MODULE__), do: GenServer.call(server, :sync_now, :timer.seconds(60))

  @impl true
  def init(opts) do
    interval_ms =
      Keyword.get(
        opts,
        :interval_ms,
        Application.get_env(:hive, :forage_github_issues, [])
        |> Keyword.get(:sync_interval_ms, @default_interval_ms)
      )

    if Keyword.get(opts, :sync_on_start, true), do: Process.send_after(self(), :tick, 0)
    schedule_tick(interval_ms)

    {:ok, %{interval_ms: interval_ms}}
  end

  @impl true
  def handle_info(:tick, state) do
    run_sync()
    schedule_tick(state.interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_call(:sync_now, _from, state) do
    {:reply, run_sync(), state}
  end

  defp schedule_tick(interval_ms), do: Process.send_after(self(), :tick, interval_ms)

  defp run_sync do
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

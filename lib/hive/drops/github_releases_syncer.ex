defmodule Hive.Drops.GitHubReleasesSyncer do
  @moduledoc """
  Periodically reconciles the `drops` table with the latest releases
  from every GitHub repository connected to a meadow.

  The syncer ticks on startup and then every `:interval_ms` (default 15
  minutes). When the GitHub App is not configured it keeps running but
  logs and skips, mirroring `Hive.Forage.GitHubIssueSyncer`.
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias Hive.Audit
  alias Hive.Drops
  alias Hive.GitHub.Client
  alias Hive.GitHub.Releases
  alias Hive.Meadows.GitHubRepository
  alias Hive.Meadows.Meadow
  alias Hive.Repo

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
    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)

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
        Audit.put_context(%{interface: "worker"})

        list_meadow_repositories()
        |> Enum.each(&sync_meadow_repository/1)

        :ok

      {:error, {:not_configured, _missing}} ->
        Logger.debug("[Drops.GitHubReleasesSyncer] GitHub App not configured; skipping")
        :skipped
    end
  end

  defp list_meadow_repositories do
    query =
      from(repository in GitHubRepository,
        join: meadow in assoc(repository, :meadows),
        preload: [meadows: meadow]
      )

    Repo.all(query)
    |> Enum.flat_map(fn repository ->
      Enum.map(repository.meadows, fn meadow -> {meadow, repository} end)
    end)
  end

  defp sync_meadow_repository({%Meadow{} = meadow, %GitHubRepository{} = repository}) do
    case Releases.list_releases(repository) do
      {:ok, releases} ->
        Enum.each(releases, fn release ->
          upsert_release_drop(meadow, repository, release)
        end)

      {:error, reason} ->
        Logger.warning(
          "[Drops.GitHubReleasesSyncer] Failed to sync #{repository.owner}/#{repository.name}: " <>
            inspect(reason)
        )
    end
  end

  defp upsert_release_drop(meadow, repository, %Releases{} = release) do
    external_id = "#{repository.owner}/#{repository.name}@#{release.tag_name || ""}"

    attrs = %{
      github_repository_id: repository.id,
      source_type: :github_release,
      external_id: external_id,
      title: release.name || release.tag_name || "Release",
      body: release.body,
      url:
        release.html_url ||
          "https://github.com/#{repository.owner}/#{repository.name}/releases/tag/#{release.tag_name}",
      published_at: parse_timestamp(release.published_at || release.created_at),
      version: release.tag_name
    }

    case Drops.upsert_release_drop(attrs) do
      {:ok, drop} ->
        Drops.replace_drop_meadows(drop, [meadow.id])
        record_audit(drop, meadow, repository)
        Hive.Drops.GitHubReleaseRewriteWorker.enqueue(drop)
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Drops.GitHubReleasesSyncer] Failed to upsert release #{external_id}: " <>
            inspect(reason)
        )
    end
  end

  defp record_audit(drop, meadow, repository) do
    if drop.inserted_at == drop.updated_at do
      Audit.record(:"drop.ingested", %{
        target_type: "drop",
        target_id: drop.id,
        target_label: drop.title,
        metadata: %{
          source_type: "github_release",
          repository: "#{repository.owner}/#{repository.name}",
          meadow: meadow.name,
          path: "/drops"
        }
      })
    end
  end

  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(""), do: nil

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_timestamp(_value), do: nil
end

defmodule Hive.Drops.GitHubReleasesSyncer do
  @moduledoc """
  Periodically reconciles the `drops` table with user-facing drop items
  generated from the latest releases from every GitHub repository
  connected to a domain.

  The syncer ticks on startup and then every `:interval_ms` (default 15
  minutes). When the GitHub App is not configured it keeps running but
  logs and skips, mirroring `Hive.Forage.GitHubIssueSyncer`.
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias Hive.Audit
  alias Hive.Drops
  alias Hive.Drops.ReleaseDropItems
  alias Hive.GitHub.Client
  alias Hive.GitHub.Releases
  alias Hive.Domains.GitHubRepository
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
    item_generator = Keyword.get(opts, :item_generator, &ReleaseDropItems.generate/3)
    generator_opts = Keyword.get(opts, :generator_opts, [])

    if Keyword.get(opts, :sync_on_start, true), do: Process.send_after(self(), :tick, 0)
    schedule_tick(interval_ms)

    {:ok,
     %{
       generator_opts: generator_opts,
       interval_ms: interval_ms,
       item_generator: item_generator
     }}
  end

  @impl true
  def handle_info(:tick, state) do
    run_sync(state)
    schedule_tick(state.interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_call(:sync_now, _from, state) do
    {:reply, run_sync(state), state}
  end

  defp schedule_tick(interval_ms), do: Process.send_after(self(), :tick, interval_ms)

  defp run_sync(state) do
    case Client.config() do
      {:ok, _config} ->
        Audit.put_context(%{interface: "worker"})

        list_project_repositories()
        |> Enum.each(&sync_project_repository(&1, state))

        :ok

      {:error, {:not_configured, _missing}} ->
        Logger.debug("[Drops.GitHubReleasesSyncer] GitHub App not configured; skipping")
        :skipped
    end
  end

  defp list_project_repositories do
    query =
      from(repository in GitHubRepository,
        where: not is_nil(repository.project_id),
        preload: [project: :domains]
      )

    Repo.all(query)
  end

  defp sync_project_repository(%GitHubRepository{project: project} = repository, state) do
    domains = project.domains

    case Releases.list_releases(repository) do
      {:ok, releases} ->
        Enum.each(releases, fn release ->
          upsert_release_items(domains, repository, release, state)
        end)

      {:error, reason} ->
        Logger.warning(
          "[Drops.GitHubReleasesSyncer] Failed to sync #{repository.owner}/#{repository.name}: " <>
            inspect(reason)
        )
    end
  end

  defp upsert_release_items(domains, repository, %Releases{} = release, state) do
    case state.item_generator.(repository, release, state.generator_opts) do
      {:ok, items} ->
        Enum.each(items, fn item ->
          upsert_release_item_drop(domains, repository, release, item)
        end)

      :skipped ->
        Logger.debug(
          "[Drops.GitHubReleasesSyncer] Skipping release #{release_label(repository, release)} because release drop item generation is unavailable"
        )

      {:error, reason} ->
        Logger.warning(
          "[Drops.GitHubReleasesSyncer] Failed to generate drop items for release " <>
            release_label(repository, release) <> ": " <> inspect(reason)
        )
    end
  end

  defp upsert_release_item_drop(domains, repository, release, item) do
    attrs = %{
      github_repository_id: repository.id,
      source_type: :github_release,
      external_id: release_item_external_id(repository, release, item),
      title: item.title,
      body: item.body,
      url: List.first(item.source_urls) || release.html_url,
      published_at: parse_timestamp(release.published_at || release.created_at),
      version: release.tag_name
    }

    case Drops.upsert_drop(attrs) do
      {:ok, drop} ->
        record_audit(drop, domains, repository, release, item)

        if is_nil(drop.classified_at) do
          Hive.Drops.DomainClassificationWorker.enqueue(drop.id)
        end

        :ok

      {:error, reason} ->
        Logger.warning(
          "[Drops.GitHubReleasesSyncer] Failed to upsert release drop item " <>
            inspect(item.title) <> ": " <> inspect(reason)
        )
    end
  end

  defp record_audit(drop, domains, repository, release, item) do
    if drop.inserted_at == drop.updated_at do
      Audit.record(:"drop.ingested", %{
        target_type: "drop",
        target_id: drop.id,
        target_label: drop.title,
        metadata: %{
          source_type: "github_release",
          repository: "#{repository.owner}/#{repository.name}",
          release: release.tag_name,
          references: item.source_urls,
          domains: Enum.map_join(domains, ", ", & &1.name),
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

  defp release_item_external_id(repository, release, item) do
    release_key =
      release.tag_name || release.html_url || release.published_at || release.created_at ||
        "untagged"

    item_key =
      item.source_urls
      |> Enum.sort()
      |> Enum.join("\n")
      |> hash_key()

    "#{repository.owner}/#{repository.name}@#{release_key}:#{item_key}"
  end

  defp release_label(repository, release) do
    release_key = release.tag_name || release.html_url || release.published_at || "untagged"
    "#{repository.owner}/#{repository.name}@#{release_key}"
  end

  defp hash_key(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end

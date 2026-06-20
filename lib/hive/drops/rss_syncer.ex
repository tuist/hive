defmodule Hive.Drops.RssSyncer do
  @moduledoc """
  Periodically polls every enabled RSS/Atom drop source registered
  through `/ops/drops` and upserts each entry into the `drops` table.

  Mirrors `Hive.Drops.GitHubReleasesSyncer`: a single GenServer ticks on
  startup and then every `:interval_ms` (default 15 minutes). Failures
  per source are recorded on the source row (`last_error` /
  `last_error_at`) so admins can spot broken feeds from the UI.
  """

  use GenServer

  require Logger

  alias Hive.Audit
  alias Hive.Drops
  alias Hive.Drops.DropSource
  alias Hive.Drops.Rss

  @default_interval_ms :timer.minutes(15)
  @user_agent "hive-drops-rss/1.0"
  @timeout_ms :timer.seconds(15)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc "Trigger a sync immediately. Returns once the run finishes."
  def sync_now(server \\ __MODULE__), do: GenServer.call(server, :sync_now, :timer.seconds(60))

  @doc "Synchronously poll a single source. Used by the dashboard's manual sync action."
  def sync_source(%DropSource{} = source), do: poll_source(source)

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
    Audit.put_context(%{interface: "worker"})

    Drops.list_pollable_sources()
    |> Enum.each(&poll_source/1)

    :ok
  end

  defp poll_source(%DropSource{} = source) do
    case fetch(source.url) do
      {:ok, body} ->
        case Rss.parse(body) do
          {:ok, entries} ->
            Enum.each(entries, &upsert_entry(source, &1))
            Drops.record_source_poll(source, :ok)
            :ok

          {:error, reason} ->
            Logger.warning("[Drops.RssSyncer] Failed to parse #{source.url}: " <> inspect(reason))

            Drops.record_source_poll(source, {:error, reason})
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("[Drops.RssSyncer] Failed to fetch #{source.url}: " <> inspect(reason))

        Drops.record_source_poll(source, {:error, reason})
        {:error, reason}
    end
  end

  defp upsert_entry(%DropSource{id: source_id} = source, entry) do
    attrs = %{
      drop_source_id: source_id,
      source_type: :rss,
      external_id: entry.external_id,
      title: entry.title || source.label || source.url,
      body: entry.body,
      url: entry.url || source.url,
      published_at: entry.published_at
    }

    case Drops.upsert_drop(attrs) do
      {:ok, drop} ->
        record_audit(drop, source)

        if is_nil(drop.classified_at) do
          Hive.Drops.DomainClassificationWorker.enqueue(drop.id)
        end

      {:error, reason} ->
        Logger.warning(
          "[Drops.RssSyncer] Failed to upsert entry from #{source.url}: " <> inspect(reason)
        )
    end
  end

  defp record_audit(drop, %DropSource{} = source) do
    if drop.inserted_at == drop.updated_at do
      Audit.record(:"drop.ingested", %{
        target_type: "drop",
        target_id: drop.id,
        target_label: drop.title,
        metadata: %{
          source_type: "rss",
          source_url: source.url,
          path: "/drops"
        }
      })
    end
  end

  defp fetch(url) do
    case Req.get(url,
           receive_timeout: @timeout_ms,
           connect_options: [timeout: @timeout_ms],
           headers: [
             {"user-agent", @user_agent},
             {"accept",
              "application/atom+xml,application/rss+xml,application/xml;q=0.9,*/*;q=0.5"}
           ],
           decode_body: false
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end
end

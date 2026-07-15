defmodule Hive.Drops.RssSyncer do
  @moduledoc """
  Periodically polls every enabled RSS/Atom drop source registered
  through `/ops/drops` and upserts each entry into the `drops` table.

  The worker is scheduled from Oban's cron configuration. Failures per
  source are recorded on the source row (`last_error` / `last_error_at`)
  so admins can spot broken feeds from the UI.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [fields: [:worker, :queue, :args], period: 60, states: :incomplete]

  require Logger

  alias Hive.Audit
  alias Hive.Drops
  alias Hive.Drops.DomainClassificationWorker
  alias Hive.Drops.DropSource
  alias Hive.Drops.Rss

  @user_agent "hive-drops-rss/1.0"
  @timeout_ms :timer.seconds(15)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"drop_source_id" => source_id}}) do
    sync_source_by_id(source_id)
  end

  def perform(%Oban.Job{}) do
    sync_now()
  end

  def enqueue_source(%DropSource{id: source_id}) do
    %{"drop_source_id" => source_id}
    |> new()
    |> Oban.insert()
  end

  @doc "Runs the feed sync immediately and returns when it finishes."
  def sync_now, do: run_sync()

  @doc "Synchronously poll a single source. Used by the dashboard's manual sync action."
  def sync_source(%DropSource{} = source), do: poll_source(source)

  defp run_sync do
    Audit.put_context(%{interface: "worker"})

    Drops.list_pollable_sources()
    |> Enum.each(&poll_source/1)

    :ok
  end

  defp sync_source_by_id(source_id) do
    case Drops.get_drop_source(source_id) do
      %DropSource{} = source ->
        case sync_source(source) do
          :ok -> :ok
          {:error, _reason} -> :ok
        end

      nil ->
        :ok
    end
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

        if is_nil(drop.classified_at) and is_nil(drop.classification_failed_at) do
          DomainClassificationWorker.enqueue(drop.id)
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
          number: to_string(drop.number),
          path: Drops.public_path(drop)
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

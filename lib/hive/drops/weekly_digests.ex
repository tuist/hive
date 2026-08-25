defmodule Hive.Drops.WeeklyDigests do
  @moduledoc """
  Claims completed weeks, builds bounded public drop context, and persists
  one durable narrated digest per week.
  """

  import Ecto.Query

  alias Hive.Agents.Errors
  alias Hive.Drops
  alias Hive.Drops.Agents.WeeklyDigestAgent
  alias Hive.Drops.WeeklyDigest
  alias Hive.Notifications
  alias Hive.Repo

  @max_drops 40
  @max_drop_body_length 1_500
  @claim_timeout_seconds 300
  @default_page_size 10
  @publication_time ~T[17:00:00]
  @reconciliation_window_weeks 8

  def latest_publishable_week(now \\ DateTime.utc_now()) do
    today = DateTime.to_date(now)
    current_week_start = Date.add(today, 1 - Date.day_of_week(today))

    if current_workweek_publishable?(now) do
      {current_week_start, Date.add(current_week_start, 4)}
    else
      week_start = Date.add(current_week_start, -7)
      {week_start, Date.add(week_start, 4)}
    end
  end

  def generate_latest_week(opts \\ []) do
    {week_start, _week_end} =
      latest_publishable_week(Keyword.get(opts, :now, DateTime.utc_now()))

    generate_for_week(week_start, Keyword.delete(opts, :now))
  end

  def generate_publishable_weeks(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    {latest_week_start, _week_end} = latest_publishable_week(now)

    [latest_week_start | recoverable_week_starts(latest_week_start)]
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&generate_for_week(&1, Keyword.delete(opts, :now)))
  end

  def generate_for_week(%Date{} = week_start, opts \\ []) do
    week_end = Date.add(week_start, 4)

    case current_result(week_start) do
      {:done, digest} ->
        {:ok, digest, :existing}

      {:empty, digest} ->
        drops =
          Drops.list_drops_between(week_start, Date.add(week_end, 1),
            user: nil,
            limit: @max_drops
          )

        if drops == [] do
          {:ok, digest, :existing}
        else
          generate_claimed_digest(week_start, week_end, drops, opts, reopen_empty?: true)
        end

      :continue ->
        drops =
          Drops.list_drops_between(week_start, Date.add(week_end, 1),
            user: nil,
            limit: @max_drops
          )

        generate_or_record_empty(week_start, week_end, drops, opts)
    end
  end

  def list_published(opts \\ []) do
    limit = Keyword.get(opts, :limit, 52)

    published_query()
    |> order_by([digest], desc: digest.week_start)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_published_page(opts \\ []) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    page_size = opts |> Keyword.get(:page_size, @default_page_size) |> normalize_page_size()

    base =
      published_query()
      |> filter_search(Keyword.get(opts, :query))
      |> filter_year(Keyword.get(opts, :year))

    total_entries = Repo.aggregate(base, :count, :id)
    total_pages = max(1, div(total_entries + page_size - 1, page_size))
    page = min(page, total_pages)

    digests =
      base
      |> order_by([digest], desc: digest.week_start)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()

    {digests,
     %{
       current_page: page,
       page_size: page_size,
       total_entries: total_entries,
       total_pages: total_pages
     }}
  end

  def published_years do
    WeeklyDigest
    |> where([digest], digest.status == :published)
    |> select([digest], fragment("EXTRACT(YEAR FROM ?)::integer", digest.week_start))
    |> distinct(true)
    |> order_by([digest], desc: fragment("EXTRACT(YEAR FROM ?)::integer", digest.week_start))
    |> Repo.all()
  end

  def latest_published do
    WeeklyDigest
    |> where([digest], digest.status == :published)
    |> order_by([digest], desc: digest.week_start)
    |> limit(1)
    |> Repo.one()
  end

  def get_published_by_week_start(%Date{} = week_start) do
    Repo.get_by(WeeklyDigest, week_start: week_start, status: :published)
  end

  def fetch_published("latest") do
    case latest_published() do
      nil -> {:error, :not_found}
      digest -> {:ok, digest}
    end
  end

  def fetch_published(reference) when is_binary(reference) do
    with {:ok, week_start} <- reference_week_start(reference),
         %WeeklyDigest{} = digest <- get_published_by_week_start(week_start) do
      {:ok, digest}
    else
      _other -> {:error, :not_found}
    end
  end

  def public_path(%WeeklyDigest{week_start: week_start}),
    do: "/drops/digest/#{Date.to_iso8601(week_start)}"

  defp published_query do
    where(WeeklyDigest, [digest], digest.status == :published)
  end

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  defp filter_search(query, text) when is_binary(text) do
    pattern = "%" <> escape_like(text) <> "%"

    where(
      query,
      [digest],
      ilike(digest.title, ^pattern) or ilike(digest.summary, ^pattern) or
        ilike(digest.body, ^pattern)
    )
  end

  defp filter_year(query, year) when is_integer(year) do
    where(query, [digest], fragment("EXTRACT(YEAR FROM ?)::integer", digest.week_start) == ^year)
  end

  defp filter_year(query, _year), do: query

  defp normalize_page_size(size) when is_integer(size) and size > 0, do: min(size, 100)
  defp normalize_page_size(_size), do: @default_page_size

  defp current_workweek_publishable?(now) do
    case Date.day_of_week(DateTime.to_date(now)) do
      day when day > 5 -> true
      5 -> Time.compare(DateTime.to_time(now), @publication_time) != :lt
      _other -> false
    end
  end

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp generate_or_record_empty(week_start, week_end, [], _opts) do
    with {:claimed, digest} <- claim_week(week_start, week_end),
         {:ok, digest} <- update_digest(digest, %{status: :empty, drop_ids: []}) do
      {:ok, digest, :empty}
    else
      {:existing, digest} -> {:ok, digest, :existing}
      {:busy, digest} -> {:ok, digest, :busy}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_or_record_empty(week_start, week_end, drops, opts) do
    agents_enabled? = Keyword.get(opts, :agents_enabled?, &Hive.Agents.enabled?/0)

    if agents_enabled?.() do
      generate_claimed_digest(week_start, week_end, drops, opts)
    else
      :skipped
    end
  end

  defp generate_claimed_digest(week_start, week_end, drops, opts, claim_opts \\ []) do
    with {:claimed, digest} <- claim_week(week_start, week_end, claim_opts),
         {:ok, output} <- run_generator(build_input(week_start, week_end, drops), opts),
         {:ok, attrs} <- normalize_output(output),
         {:ok, digest} <- publish(digest, drops, attrs) do
      {:ok, digest, :published}
    else
      {:error, :llm_not_configured} ->
        delete_generating_digest(week_start)
        :skipped

      {:error, reason} ->
        mark_failed(week_start, reason)
        {:error, reason}

      {:existing, digest} ->
        {:ok, digest, :existing}

      {:busy, digest} ->
        {:ok, digest, :busy}
    end
  end

  defp current_result(week_start) do
    case Repo.get_by(WeeklyDigest, week_start: week_start) do
      %WeeklyDigest{status: :published} = digest ->
        {:done, digest}

      %WeeklyDigest{status: :empty} = digest ->
        {:empty, digest}

      _other ->
        :continue
    end
  end

  defp claim_week(week_start, week_end, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    id = Ecto.UUID.generate()

    {inserted, _rows} =
      Repo.insert_all(
        WeeklyDigest,
        [
          %{
            id: id,
            week_start: week_start,
            week_end: week_end,
            status: :generating,
            drop_ids: [],
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:week_start]
      )

    if inserted == 1 do
      {:claimed, Repo.get!(WeeklyDigest, id)}
    else
      reclaim_existing(week_start, now, opts)
    end
  end

  defp reclaim_existing(week_start, now, opts) do
    Repo.transaction(fn ->
      digest =
        WeeklyDigest
        |> where([digest], digest.week_start == ^week_start)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      cond do
        digest.status == :published ->
          {:existing, digest}

        digest.status == :empty ->
          reclaim_empty_digest(digest, opts)

        digest.status == :failed or stale_claim?(digest, now) ->
          reclaim_digest(digest)

        true ->
          {:busy, digest}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp stale_claim?(%WeeklyDigest{status: :generating, updated_at: updated_at}, now) do
    DateTime.diff(now, updated_at, :second) >= @claim_timeout_seconds
  end

  defp stale_claim?(_digest, _now), do: false

  defp reclaim_digest(digest) do
    case update_digest(digest, %{status: :generating, failure_reason: nil}) do
      {:ok, reclaimed} -> {:claimed, reclaimed}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp reclaim_empty_digest(digest, opts) do
    if Keyword.get(opts, :reopen_empty?, false) do
      reclaim_digest(digest)
    else
      {:existing, digest}
    end
  end

  defp build_input(week_start, week_end, drops) do
    %{
      week_start: Date.to_iso8601(week_start),
      week_end: Date.to_iso8601(week_end),
      drops: Enum.map(drops, &drop_input/1)
    }
  end

  defp drop_input(drop) do
    %{
      id: to_string(drop.number),
      title: drop.title,
      body: truncate(drop.body || "", @max_drop_body_length),
      url: Drops.public_path(drop),
      source_url: drop.url || "",
      published_at: iso8601(drop.published_at || drop.updated_at),
      domains: Enum.map(drop.domains || [], & &1.name),
      projects: drop |> Drops.projects_for_drop() |> Enum.map(& &1.name)
    }
  end

  defp run_generator(input, opts) do
    runner = Keyword.get(opts, :runner, &run_agent(&1, opts))
    runner.(input)
  end

  defp run_agent(input, opts) do
    agent = Keyword.get(opts, :agent, WeeklyDigestAgent)
    agent_opts = Keyword.get(opts, :agent_opts, [])
    agent.generate(input, agent_opts)
  end

  defp normalize_output(output) when is_map(output) do
    title = output |> value(:title) |> normalize_text()
    summary = output |> value(:summary) |> normalize_text()
    body = output |> value(:body) |> normalize_text()

    if title && summary && body do
      {:ok, %{title: title, summary: summary, body: body}}
    else
      {:error, :invalid_weekly_digest}
    end
  end

  defp normalize_output(_output), do: {:error, :invalid_weekly_digest}

  defp publish(digest, drops, attrs) do
    attrs =
      attrs
      |> Map.put(:status, :published)
      |> Map.put(:drop_ids, Enum.map(drops, & &1.id))
      |> Map.put(:published_at, DateTime.utc_now() |> DateTime.truncate(:second))
      |> Map.put(:failure_reason, nil)

    Repo.transaction(fn ->
      case update_digest(digest, attrs) do
        {:ok, published_digest} ->
          Notifications.publish!(%{
            deduplication_key: "weekly_drop_digest_published:#{published_digest.id}",
            type: :weekly_drop_digest_published,
            resource_type: "drop_digest",
            resource_id: published_digest.id,
            data: %{"week_start" => Date.to_iso8601(published_digest.week_start)}
          })

          {:ok, published_digest}

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp mark_failed(week_start, reason) do
    case Repo.get_by(WeeklyDigest, week_start: week_start, status: :generating) do
      nil -> :ok
      digest -> update_digest(digest, %{status: :failed, failure_reason: failure_reason(reason)})
    end
  end

  defp delete_generating_digest(week_start) do
    WeeklyDigest
    |> where([digest], digest.week_start == ^week_start and digest.status == :generating)
    |> Repo.delete_all()
  end

  defp update_digest(digest, attrs) do
    digest
    |> WeeklyDigest.changeset(attrs)
    |> Repo.update()
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp normalize_text(value) when is_binary(value) do
    value
    |> String.replace(" — ", ": ")
    |> String.replace("—", "-")
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp normalize_text(_value), do: nil

  defp reference_week_start(reference) do
    candidate =
      reference
      |> String.trim()
      |> URI.parse()
      |> case do
        %URI{path: path} when is_binary(path) and path != "" ->
          path |> String.split("/", trim: true) |> List.last()

        _uri ->
          nil
      end

    if is_binary(candidate), do: Date.from_iso8601(candidate), else: :error
  end

  defp truncate(value, max_length) do
    if String.length(value) > max_length,
      do: String.slice(value, 0, max_length),
      else: value
  end

  defp failure_reason(reason) do
    reason
    |> Errors.sanitize_reason(:weekly_digest_generation_failed)
    |> inspect()
    |> String.slice(0, 500)
  end

  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp iso8601(%NaiveDateTime{} = datetime),
    do: datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp recoverable_week_starts(latest_week_start) do
    earliest_week_start = Date.add(latest_week_start, -7 * @reconciliation_window_weeks)

    WeeklyDigest
    |> where(
      [digest],
      digest.status in [:empty, :failed] and digest.week_start >= ^earliest_week_start
    )
    |> select([digest], digest.week_start)
    |> Repo.all()
  end
end

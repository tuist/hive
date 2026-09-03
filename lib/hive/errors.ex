defmodule Hive.Errors do
  @moduledoc """
  Error tracking for Hive: a Sentry-compatible ingest endpoint plus
  the storage that backs it.

  Events land as Sentry envelopes on `POST /api/:project_id/envelope/`,
  are parsed into `Hive.Errors.SentryEvent`, grouped into
  `Hive.Errors.Issue` records by fingerprint (Postgres), and appended
  as rows to the `errors_events` table in ClickHouse.

  This surface is private by design. Errors frequently carry sensitive
  data (user identifiers, request payloads, stack-trace context), so
  every dashboard, feed, and MCP tool that reads issues or events
  requires an authenticated org member. The ingest endpoint itself is
  public but authenticated by DSN public key.
  """

  import Ecto.Query

  alias Hive.Errors.Fingerprint
  alias Hive.Errors.Issue
  alias Hive.Errors.ProjectKey
  alias Hive.Errors.SentryEvent
  alias Hive.IngestRepo
  alias Hive.Projects.Project
  alias Hive.Repo

  @doc """
  Whether error tracking is available on this instance. Requires the
  ClickHouse repositories to be started, which is gated by
  `HIVE_CLICKHOUSE_ENABLED`.
  """
  def enabled?, do: Hive.Errors.Availability.enabled?()

  @doc """
  Records a parsed Sentry event against a project. Upserts the owning
  issue in Postgres and appends the event to ClickHouse. Returns the
  updated issue.

  Callers that received raw SDK JSON should build the `SentryEvent` via
  `Hive.Errors.SentryEvent.parse/1` first.
  """
  @spec record_event(Project.t(), SentryEvent.t()) ::
          {:ok, Issue.t()} | {:error, :not_configured | term()}
  def record_event(%Project{} = project, %SentryEvent{} = event) do
    if enabled?() do
      fingerprint = Fingerprint.compute(event)

      with {:ok, issue} <- upsert_issue(project, event, fingerprint),
           :ok <- insert_event(project, issue, event, fingerprint) do
        {:ok, issue}
      end
    else
      {:error, :not_configured}
    end
  end

  defp upsert_issue(project, event, fingerprint) do
    now = event.timestamp || DateTime.utc_now()
    title = SentryEvent.title(event) |> truncate(500)
    culprit = SentryEvent.culprit(event) |> truncate(500)

    attrs = %{
      project_id: project.id,
      fingerprint: fingerprint,
      title: title,
      culprit: culprit,
      level: String.to_atom(event.level),
      platform: event.platform,
      first_seen: now,
      last_seen: now,
      event_count: 1
    }

    changeset = Issue.changeset(%Issue{}, attrs)

    case Repo.insert(changeset,
           on_conflict: [
             inc: [event_count: 1],
             set: [
               last_seen: now,
               title: title,
               culprit: culprit,
               level: String.to_atom(event.level),
               platform: event.platform,
               status: :unresolved,
               updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
             ]
           ],
           conflict_target: [:project_id, :fingerprint],
           returning: true
         ) do
      {:ok, issue} -> {:ok, issue}
      {:error, _} = err -> err
    end
  end

  defp insert_event(project, issue, event, fingerprint) do
    row = %{
      event_id: event.event_id |> to_uuid(),
      project_id: project.id,
      issue_id: issue.id,
      fingerprint: fingerprint,
      timestamp: DateTime.truncate(event.timestamp, :microsecond),
      received_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      platform: event.platform || "other",
      level: event.level || "error",
      environment: event.environment || "production",
      release: event.release || "",
      dist: event.dist || "",
      server_name: event.server_name || "",
      transaction: event.transaction || "",
      logger: event.logger || "",
      exception_type: event.exception_type || "",
      exception_value: event.exception_value || "",
      top_frame_function: frame_field(event.top_frame, "function"),
      top_frame_module: frame_field(event.top_frame, "module"),
      top_frame_filename: frame_field(event.top_frame, "filename"),
      user_id: event.user.id || "",
      user_email: event.user.email || "",
      user_ip: event.user.ip_address || "",
      request_url: event.request.url || "",
      request_method: event.request.method || "",
      sdk_name: event.sdk_name || "",
      sdk_version: event.sdk_version || "",
      tags: event.tags,
      payload: Jason.encode!(event.payload)
    }

    case IngestRepo.insert_all("errors_events", [row], types: event_column_types()) do
      {_count, _} -> :ok
    end
  rescue
    error -> {:error, error}
  end

  # ClickHouse column types for `errors_events`, required by ecto_ch when
  # inserting into a raw table name.
  defp event_column_types do
    %{
      event_id: "UUID",
      project_id: "String",
      issue_id: "String",
      fingerprint: "FixedString(64)",
      timestamp: "DateTime64(6, 'UTC')",
      received_at: "DateTime64(6, 'UTC')",
      platform: "LowCardinality(String)",
      level: "LowCardinality(String)",
      environment: "LowCardinality(String)",
      release: "String",
      dist: "String",
      server_name: "String",
      transaction: "String",
      logger: "LowCardinality(String)",
      exception_type: "String",
      exception_value: "String",
      top_frame_function: "String",
      top_frame_module: "String",
      top_frame_filename: "String",
      user_id: "String",
      user_email: "String",
      user_ip: "String",
      request_url: "String",
      request_method: "LowCardinality(String)",
      sdk_name: "LowCardinality(String)",
      sdk_version: "LowCardinality(String)",
      tags: "Map(LowCardinality(String), String)",
      payload: "String"
    }
  end

  defp frame_field(nil, _), do: ""
  defp frame_field(frame, key) when is_map(frame), do: to_string(frame[key] || "")

  defp to_uuid(event_id) when is_binary(event_id) and byte_size(event_id) == 32 do
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
      e::binary-size(12)>> = event_id

    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  defp to_uuid(_), do: Ecto.UUID.generate()

  defp truncate(nil, _), do: nil
  defp truncate(binary, max) when is_binary(binary), do: String.slice(binary, 0, max)

  ## Issue queries

  @doc """
  Lists issues matching the given filters. Options:

    * `:project_id` — scope to a single project (required unless caller has already scoped).
    * `:status` — `:unresolved`, `:resolved`, `:ignored`, or `nil` for all.
    * `:search` — substring against title/culprit.
    * `:from`, `:to` — timeframe on `last_seen`.
    * `:limit`, `:cursor` — cursor-based pagination on `last_seen`.
  """
  def list_issues(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)

    Issue
    |> filter_project(opts[:project_id])
    |> filter_status(opts[:status])
    |> filter_search(opts[:search])
    |> filter_from(opts[:from])
    |> filter_to(opts[:to])
    |> order_by([issue], desc: issue.last_seen, desc: issue.id)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
  end

  @doc """
  Paginated variant of `list_issues/1`. Accepts the same filters plus
  `:page` (1-indexed) and `:page_size` (default 25) and returns
  `{issues, meta}` where meta includes `current_page`, `total_pages`,
  and `total_count`. Suitable for LiveView dashboards.
  """
  def paginate_issues(opts \\ []) do
    page_size = opts |> Keyword.get(:page_size, 25) |> max(1)
    page = opts |> Keyword.get(:page, 1) |> max(1)
    offset = (page - 1) * page_size

    matching_ids =
      issue_ids_matching_events(
        project_id: opts[:project_id],
        environment: opts[:environment],
        from: opts[:from],
        to: opts[:to]
      )

    base =
      Issue
      |> filter_project(opts[:project_id])
      |> filter_status(opts[:status])
      |> filter_search(opts[:search])
      |> filter_from(opts[:from])
      |> filter_to(opts[:to])
      |> filter_matching_ids(matching_ids)

    total = base |> exclude(:preload) |> Repo.aggregate(:count, :id)

    issues =
      base
      |> order_by([issue], desc: issue.last_seen, desc: issue.id)
      |> limit(^page_size)
      |> offset(^offset)
      |> preload(:project)
      |> Repo.all()

    meta = %{
      current_page: page,
      page_size: page_size,
      total_count: total,
      total_pages: max(1, div(total + page_size - 1, page_size)),
      has_previous_page?: page > 1,
      has_next_page?: page * page_size < total
    }

    {issues, meta}
  end

  @doc """
  Returns per-project unresolved issue counts as a
  `%{project_id => count}` map.
  """
  def unresolved_counts_by_project do
    Issue
    |> where([issue], issue.status == :unresolved)
    |> group_by([issue], issue.project_id)
    |> select([issue], {issue.project_id, count(issue.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp filter_project(query, nil), do: query

  defp filter_project(query, project_id),
    do: where(query, [issue], issue.project_id == ^project_id)

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: where(query, [issue], issue.status == ^status)

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  defp filter_search(query, term) when is_binary(term) do
    like = "%#{String.replace(term, "%", "\\%")}%"
    where(query, [issue], ilike(issue.title, ^like) or ilike(issue.culprit, ^like))
  end

  defp filter_from(query, nil), do: query

  defp filter_from(query, %DateTime{} = from),
    do: where(query, [issue], issue.last_seen >= ^from)

  defp filter_to(query, nil), do: query
  defp filter_to(query, %DateTime{} = to), do: where(query, [issue], issue.last_seen <= ^to)

  defp filter_matching_ids(query, :all), do: query
  defp filter_matching_ids(query, []), do: where(query, [issue], false)

  defp filter_matching_ids(query, ids) when is_list(ids),
    do: where(query, [issue], issue.id in ^ids)

  def fetch_issue(id) do
    case Repo.get(Issue, id) do
      nil -> {:error, :not_found}
      %Issue{} = issue -> {:ok, Repo.preload(issue, [:project, :assignee])}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def update_issue_status(%Issue{} = issue, status)
      when status in [:unresolved, :resolved, :ignored] do
    issue
    |> Issue.status_changeset(status)
    |> Repo.update()
  end

  ## Project key management

  def list_project_keys(project_id) do
    ProjectKey
    |> where([key], key.project_id == ^project_id)
    |> order_by([key], asc: key.inserted_at)
    |> Repo.all()
  end

  def fetch_project_key_by_public_key(public_key) when is_binary(public_key) do
    case Repo.get_by(ProjectKey, public_key: public_key) do
      nil -> {:error, :not_found}
      %ProjectKey{} = key -> {:ok, Repo.preload(key, :project)}
    end
  end

  def create_project_key(project_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("project_id", project_id)
      |> Map.put_new("public_key", ProjectKey.generate_key())
      |> Map.put_new("secret_key", ProjectKey.generate_key())
      |> Map.put_new("name", "default")

    %ProjectKey{}
    |> ProjectKey.changeset(attrs)
    |> Repo.insert()
  end

  def touch_project_key(%ProjectKey{} = key) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    from(k in ProjectKey, where: k.id == ^key.id)
    |> Repo.update_all(set: [last_used_at: now])

    :ok
  end

  @doc """
  Returns the distinct environments seen for events matching the
  filters. Used by the dashboard's environment filter dropdown.
  """
  def distinct_environments(opts \\ []) do
    if enabled?() do
      {clauses, params} = event_window_clauses(opts)

      where_sql =
        case clauses do
          [] -> ""
          list -> " WHERE " <> Enum.join(list, " AND ")
        end

      query = """
      SELECT DISTINCT environment
      FROM errors_events
      #{where_sql}
      ORDER BY environment
      """

      case Ecto.Adapters.SQL.query(Hive.ClickHouseRepo, query, params) do
        {:ok, %{rows: rows}} -> Enum.map(rows, fn [env] -> to_string(env) end)
        _ -> []
      end
    else
      []
    end
  end

  @doc """
  Returns the set of issue ids that had at least one event matching
  the given filters. Used to intersect Postgres issue queries with
  event-scoped filters like environment and time window.

  Returns `:all` when ClickHouse is disabled or no filters restrict
  the events, so callers can skip the intersection entirely.
  """
  def issue_ids_matching_events(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    environment = Keyword.get(opts, :environment)
    from = Keyword.get(opts, :from)
    to = Keyword.get(opts, :to)

    cond do
      not enabled?() ->
        :all

      is_nil(environment) and is_nil(from) and is_nil(to) ->
        :all

      true ->
        {clauses, params} = event_window_clauses(opts)

        where_sql =
          case clauses do
            [] -> ""
            list -> " WHERE " <> Enum.join(list, " AND ")
          end

        query = """
        SELECT DISTINCT issue_id
        FROM errors_events
        #{where_sql}
        """

        params =
          case project_id do
            nil -> params
            _ -> params
          end

        case Ecto.Adapters.SQL.query(Hive.ClickHouseRepo, query, params) do
          {:ok, %{rows: rows}} -> Enum.map(rows, fn [id] -> to_string(id) end)
          _ -> []
        end
    end
  end

  @doc """
  Returns per-hour event counts for many issues in a single query.
  Result: `%{issue_id => [count_per_bucket]}` ordered oldest → newest.
  Used to render the dashboard's Trend sparkline column without a
  ClickHouse round-trip per row.
  """
  def event_trends(issue_ids, %DateTime{} = from, %DateTime{} = to) when is_list(issue_ids) do
    cond do
      not enabled?() -> %{}
      issue_ids == [] -> %{}
      true -> do_event_trends(issue_ids, from, to)
    end
  end

  defp do_event_trends(issue_ids, from, to) do
    bucket_unit = bucket_unit_for(from, to)

    query = """
    SELECT
      issue_id,
      #{bucket_expr(bucket_unit)} AS bucket,
      count() AS events
    FROM errors_events
    WHERE issue_id IN {ids:Array(String)}
      AND timestamp >= {from:DateTime64(6)}
      AND timestamp <= {to:DateTime64(6)}
    GROUP BY issue_id, bucket
    ORDER BY issue_id, bucket
    """

    params = %{"ids" => issue_ids, "from" => from, "to" => to}

    case Ecto.Adapters.SQL.query(Hive.ClickHouseRepo, query, params) do
      {:ok, %{rows: rows}} ->
        buckets = time_buckets(from, to, bucket_unit)

        by_issue =
          Enum.group_by(rows, fn [issue_id, _bucket, _count] -> to_string(issue_id) end)

        Map.new(issue_ids, fn issue_id ->
          points = Map.get(by_issue, issue_id, [])
          counts_map = Map.new(points, fn [_, bucket, count] -> {bucket_key(bucket), count} end)
          series = Enum.map(buckets, fn bucket -> Map.get(counts_map, bucket_key(bucket), 0) end)
          {issue_id, series}
        end)

      _ ->
        %{}
    end
  end

  defp bucket_unit_for(from, to) do
    hours = DateTime.diff(to, from, :second) / 3600

    cond do
      hours <= 2 -> :minute
      hours <= 24 * 3 -> :hour
      hours <= 24 * 30 -> :day
      true -> :day
    end
  end

  defp bucket_expr(:minute), do: "toStartOfInterval(timestamp, INTERVAL 5 MINUTE)"
  defp bucket_expr(:hour), do: "toStartOfHour(timestamp)"
  defp bucket_expr(:day), do: "toStartOfDay(timestamp)"

  defp time_buckets(from, to, :minute) do
    stream_buckets(from, to, 300, :second)
  end

  defp time_buckets(from, to, :hour) do
    stream_buckets(from, to, 3600, :second)
  end

  defp time_buckets(from, to, :day) do
    stream_buckets(from, to, 86_400, :second)
  end

  defp stream_buckets(from, to, seconds, unit) do
    start = DateTime.add(from, 0, unit) |> DateTime.truncate(:second)
    stop = to |> DateTime.truncate(:second)

    Stream.iterate(start, &DateTime.add(&1, seconds, :second))
    |> Enum.take_while(&(DateTime.compare(&1, stop) != :gt))
  end

  defp bucket_key(%DateTime{} = dt), do: DateTime.to_unix(dt)

  defp bucket_key(%NaiveDateTime{} = dt),
    do: DateTime.from_naive!(dt, "Etc/UTC") |> DateTime.to_unix()

  defp bucket_key(int) when is_integer(int), do: int

  defp bucket_key(bin) when is_binary(bin) do
    case DateTime.from_iso8601(bin) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> 0
    end
  end

  @doc """
  Returns per-issue event counts within a time window.
  Result: `%{issue_id => count}`.
  """
  def event_counts_in_window(issue_ids, %DateTime{} = from, %DateTime{} = to)
      when is_list(issue_ids) do
    cond do
      not enabled?() ->
        %{}

      issue_ids == [] ->
        %{}

      true ->
        query = """
        SELECT issue_id, count() AS events
        FROM errors_events
        WHERE issue_id IN {ids:Array(String)}
          AND timestamp >= {from:DateTime64(6)}
          AND timestamp <= {to:DateTime64(6)}
        GROUP BY issue_id
        """

        params = %{"ids" => issue_ids, "from" => from, "to" => to}

        case Ecto.Adapters.SQL.query(Hive.ClickHouseRepo, query, params) do
          {:ok, %{rows: rows}} ->
            Map.new(rows, fn [id, count] -> {to_string(id), count} end)

          _ ->
            %{}
        end
    end
  end

  defp event_window_clauses(opts) do
    project_id = Keyword.get(opts, :project_id)
    environment = Keyword.get(opts, :environment)
    from = Keyword.get(opts, :from)
    to = Keyword.get(opts, :to)

    {clauses, params} = {[], %{}}

    {clauses, params} =
      case project_id do
        nil ->
          {clauses, params}

        pid ->
          {clauses ++ ["project_id = {project_id:String}"], Map.put(params, "project_id", pid)}
      end

    {clauses, params} =
      case environment do
        nil ->
          {clauses, params}

        "" ->
          {clauses, params}

        env ->
          {clauses ++ ["environment = {environment:String}"], Map.put(params, "environment", env)}
      end

    {clauses, params} =
      case from do
        nil ->
          {clauses, params}

        %DateTime{} ->
          {clauses ++ ["timestamp >= {from:DateTime64(6)}"], Map.put(params, "from", from)}
      end

    {clauses, params} =
      case to do
        nil -> {clauses, params}
        %DateTime{} -> {clauses ++ ["timestamp <= {to:DateTime64(6)}"], Map.put(params, "to", to)}
      end

    {clauses, params}
  end

  @doc """
  Serializes an issue for Model Context Protocol responses.
  """
  def serialize_issue(%Issue{} = issue) do
    project = issue.project

    %{
      id: issue.id,
      project_id: issue.project_id,
      project_name: project && project.name,
      fingerprint: issue.fingerprint,
      title: issue.title,
      culprit: issue.culprit,
      level: to_string(issue.level),
      platform: issue.platform,
      status: to_string(issue.status),
      event_count: issue.event_count,
      first_seen: issue.first_seen && DateTime.to_iso8601(issue.first_seen),
      last_seen: issue.last_seen && DateTime.to_iso8601(issue.last_seen),
      assignee_id: issue.assignee_id
    }
  end

  @doc """
  Serializes a project key. `endpoint_url` is the Hive host used to
  render the Data Source Name.
  """
  def serialize_project_key(%ProjectKey{} = key, endpoint_url) do
    %{
      id: key.id,
      project_id: key.project_id,
      public_key: key.public_key,
      name: key.name,
      dsn: ProjectKey.dsn(key, endpoint_url),
      last_used_at: key.last_used_at && DateTime.to_iso8601(key.last_used_at),
      inserted_at: key.inserted_at && DateTime.to_iso8601(key.inserted_at)
    }
  end

  ## Event queries (ClickHouse)

  @doc """
  Returns a per-hour count of events for the given issue within the
  window. Used by the dashboard occurrence chart and by the alerting
  agent.
  """
  def event_series(issue_id, %DateTime{} = from, %DateTime{} = to) do
    if enabled?() do
      query = """
      SELECT
        toStartOfHour(timestamp) AS bucket,
        count() AS events
      FROM errors_events
      WHERE issue_id = {issue_id:String}
        AND timestamp >= {from:DateTime64(6)}
        AND timestamp <= {to:DateTime64(6)}
      GROUP BY bucket
      ORDER BY bucket
      """

      params = %{"issue_id" => issue_id, "from" => from, "to" => to}

      {:ok, %{rows: rows}} =
        Ecto.Adapters.SQL.query(Hive.ClickHouseRepo, query, params)

      Enum.map(rows, fn [bucket, events] -> %{bucket: bucket, events: events} end)
    else
      []
    end
  end

  @doc """
  Returns the most recent events for an issue as maps, decoding the
  stored payload.
  """
  def list_events_for_issue(issue_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    from = Keyword.get(opts, :from)
    to = Keyword.get(opts, :to)

    if enabled?() do
      where_clauses = ["issue_id = {issue_id:String}"]
      params = %{"issue_id" => issue_id, "limit" => limit}

      {where_clauses, params} =
        if from do
          {where_clauses ++ ["timestamp >= {from:DateTime64(6)}"], Map.put(params, "from", from)}
        else
          {where_clauses, params}
        end

      {where_clauses, params} =
        if to do
          {where_clauses ++ ["timestamp <= {to:DateTime64(6)}"], Map.put(params, "to", to)}
        else
          {where_clauses, params}
        end

      query = """
      SELECT event_id, timestamp, level, environment, release, exception_type,
             exception_value, top_frame_function, top_frame_filename, payload
      FROM errors_events
      WHERE #{Enum.join(where_clauses, " AND ")}
      ORDER BY timestamp DESC
      LIMIT {limit:UInt32}
      """

      {:ok, %{rows: rows}} = Ecto.Adapters.SQL.query(Hive.ClickHouseRepo, query, params)

      Enum.map(rows, fn [event_id, ts, level, env, release, ex_type, ex_value, fn_, file, payload] ->
        %{
          event_id: event_id,
          timestamp: ts,
          level: level,
          environment: env,
          release: release,
          exception_type: ex_type,
          exception_value: ex_value,
          top_frame_function: fn_,
          top_frame_filename: file,
          payload: safe_decode(payload)
        }
      end)
    else
      []
    end
  end

  defp safe_decode(binary) when is_binary(binary) do
    case Jason.decode(binary) do
      {:ok, decoded} -> decoded
      _ -> %{}
    end
  end

  defp safe_decode(_), do: %{}
end

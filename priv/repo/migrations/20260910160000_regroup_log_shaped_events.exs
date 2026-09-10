defmodule Hive.Repo.DataMigrations.RegroupLogShapedEvents do
  @moduledoc """
  Refiles log-shaped events that were grouped before they had anything
  to group on.

  Events carrying no exception, no stack frames and no message — what
  some Software Development Kits emit when forwarding tracing or
  logging output — used to reduce to four blank grouping components,
  so every one of them in a project hashed the same three separators
  and collapsed into a single catch-all issue named after an event
  identifier. `20260910...regroup_literal_default_fingerprints.exs`
  left them alone: its signature is a `{{ default }}` fingerprint
  array, and the Software Development Kits that emit these send none.

  Grouping now falls back to the identity such an event does carry —
  its logger, normalized transaction, level, and Rust tracing event
  name — but, as ever, only for events received after that shipped.
  On Tuist's instance the catch-all holds 247 events of one otel
  span-export failure, stranded under `Event c59fc1e9...` while every
  future occurrence of the same error opens a new issue beside it.
  This joins the two.

  ## Why the grouping rules are copied in here

  Same reason as the sibling migration: a migration is permanent and
  the modules it would call are not, so `Hive.Errors.Fingerprint` and
  `Hive.Errors.SentryEvent` are not called. The slice copied below is
  small, because the events this touches are log-shaped by
  construction — the scan filters on the exception-derived columns
  being empty, so there is no exception or stack frame to parse.

  ## What it touches

  Only events it can positively identify: hashing the components as
  they were — four blanks, expanded into the event's fingerprint array
  when it has one — reproduces the fingerprint the row is stored
  under, and grouping them the new way lands somewhere else. Anything
  that fails either test is left alone.

  Mechanics match the sibling migration: `fingerprint` is part of
  `errors_events`' sorting key so events are copied to their corrected
  fingerprint and the originals deleted, each group cleared at its
  destination first so an interrupted run can be retried; issue rows
  only widen; emptied issues are deleted; alerts are not evaluated.
  """
  use Ecto.Migration

  import Ecto.Query

  require Logger

  # The ClickHouse work is not transactional and the scan is long
  # enough that there is no reason to hold a Postgres transaction open
  # across it. The migration lock is left on: the chart runs migrations
  # from an init container on every pod, so above one replica two of
  # them start this at the same time, and ClickHouse migrations take no
  # lock of their own — `Ecto.Adapters.ClickHouse.lock_for_migrations/3`
  # just calls the function it is given.
  @disable_ddl_transaction true

  @batch_size 500

  @nothing_to_do %{scanned: 0, moved: 0, issues_written: 0, issues_deleted: 0}

  # UUIDv5 namespace for issue ids, copied from `Hive.Errors.Issue`.
  @uuid_namespace <<0x6F, 0x66, 0xEA, 0xF6, 0x2C, 0x18, 0x5C, 0x11, 0xA5, 0xB2, 0xD1, 0xF4, 0x5D,
                    0x8D, 0x22, 0x1A>>

  @default_token ~r/\A\{\{\s*default\s*\}\}\z/

  @levels ~w(fatal error warning info debug)

  # What an event with no exception, frames or message reduced to
  # before grouping had a fallback.
  @blank_components ["", "", "", ""]

  @carried ~w(
    event_id project_id domain_id timestamp received_at platform level
    environment release dist server_name transaction logger exception_type
    exception_value top_frame_function top_frame_module top_frame_filename
    user_id user_email user_ip request_url request_method sdk_name sdk_version
    tags payload
  )

  def up do
    {:ok, _pid} = ensure_ingest_repo()
    Logger.info("errors: refiling log-shaped events onto their identity")

    # Bound to its own variable: `Logger` only evaluates its message
    # when the level is enabled, so interpolating this call would skip
    # the repair wherever the level is above :info while still
    # recording the migration as applied.
    report = run(DateTime.utc_now())
    Logger.info("errors: refiled #{inspect(report)}")

    :ok
  end

  # Irreversible: the superseded fingerprint described a grouping that
  # no longer exists, so there is nothing correct to restore.
  def down, do: :ok

  @doc """
  Refiles every affected event at or before `cutoff` and rebuilds the
  issues involved. Public so the grouping decisions can be tested.
  """
  def run(cutoff, batch_size \\ @batch_size) do
    if events_table?(), do: refile(cutoff, batch_size), else: @nothing_to_do
  end

  # Postgres migrations run before the ClickHouse ones (`ecto_repos` is
  # ordered `[Hive.Repo, Hive.IngestRepo]`), so on a first install the
  # events table does not exist yet when this runs. There is nothing
  # stored to refile then — but querying it regardless aborts the
  # migration, and with it the deploy.
  defp events_table? do
    %{rows: [[exists]]} = Hive.IngestRepo.query!("EXISTS TABLE errors_events", %{})
    exists == 1
  end

  defp refile(cutoff, batch_size) do
    state =
      scan(cutoff, batch_size, %{
        scanned: 0,
        moved: 0,
        groups: %{},
        vacated: MapSet.new(),
        retained: MapSet.new(),
        cursor: nil
      })

    %{
      scanned: state.scanned,
      moved: state.moved,
      issues_written: upsert_issues(state.groups),
      issues_deleted: delete_emptied_issues(state)
    }
  end

  ## Scan

  defp scan(cutoff, batch_size, state) do
    case read_batch(cutoff, batch_size, state.cursor) do
      [] ->
        state

      rows ->
        rows |> Enum.filter(& &1.affected?) |> move()

        scan(cutoff, batch_size, %{
          Enum.reduce(rows, state, &classify/2)
          | cursor: {List.last(rows).timestamp, List.last(rows).event_id}
        })
    end
  end

  # The exception-derived columns being empty is what makes an event
  # log-shaped, and the ingest path wrote them with the same parser
  # that produced the grouping components. Filtering on them here
  # means the scan only reads candidates, and that nothing below has
  # to parse an exception or pick a stack frame.
  defp read_batch(cutoff, batch_size, cursor) do
    {keyset, params} = keyset(cursor)

    %{rows: rows} =
      Hive.IngestRepo.query!(
        """
        SELECT toString(event_id), project_id, domain_id, fingerprint,
               timestamp, level, platform, logger, transaction, payload
        FROM errors_events
        WHERE timestamp <= {cutoff:DateTime64(6)}
          AND exception_type = ''
          AND exception_value = ''
          AND top_frame_function = ''
          AND top_frame_module = ''
          AND top_frame_filename = ''#{keyset}
        ORDER BY timestamp, event_id
        LIMIT {limit:UInt32}
        """,
        params |> Map.put("cutoff", cutoff) |> Map.put("limit", batch_size)
      )

    Enum.map(rows, &decorate/1)
  end

  defp keyset(nil), do: {"", %{}}

  defp keyset({timestamp, event_id}) do
    {"\n          AND (timestamp, event_id) > ({after_ts:DateTime64(6)}, {after_id:UUID})",
     %{"after_ts" => timestamp, "after_id" => event_id}}
  end

  ## Grouping rules, frozen as of the release that added the fallback

  @doc """
  Decides whether one stored row was grouped before log-shaped events
  had an identity to group on, and if so what its fingerprint should
  be now. Takes the row as `read_batch/3` selects it. Public for tests.
  """
  def decorate([
        event_id,
        project_id,
        domain_id,
        fingerprint,
        ts,
        level,
        platform,
        logger,
        transaction,
        payload
      ]) do
    decoded = decode(payload)

    event = %{
      message: message(decoded),
      tracing_name: tracing_name(decoded),
      override: fingerprint_override(decoded["fingerprint"]),
      logger: logger,
      transaction: transaction,
      level: level
    }

    # Log-shaped means every component was blank, which the columns
    # already established except for the message.
    blank? = normalize_text(event.message || "") == ""

    was = blank? and fingerprint_with(event.override, @blank_components) == fingerprint
    now = blank? and fingerprint_with(event.override, identity_components(event))

    %{
      event_id: event_id,
      project_id: project_id,
      domain_id: domain_id,
      fingerprint: fingerprint,
      timestamp: ts,
      level: level,
      platform: platform,
      title: title(event, event_id),
      culprit: presence(transaction),
      affected?: was and now != fingerprint,
      corrected: was and now
    }
  end

  defp fingerprint_with(nil, components), do: components |> Enum.join("|") |> hash()

  defp fingerprint_with(override, components) do
    override
    |> Enum.flat_map(fn part ->
      if Regex.match?(@default_token, part), do: components, else: [part]
    end)
    |> Enum.join("|")
    |> hash()
  end

  # The identity a log-shaped event does carry. `transaction` is the
  # one free-text component, so it gets the same normalization a
  # message would: transactions named per record would otherwise
  # fragment into an issue per record.
  defp identity_components(event) do
    [
      event.logger || "",
      normalize_text(event.transaction || ""),
      event.level || "",
      event.tracing_name || ""
    ]
  end

  defp normalize_text(binary) when is_binary(binary) do
    binary
    |> String.replace(~r/0x[0-9a-fA-F]+/, "0x*")
    |> String.replace(~r/\d+/, "N")
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 200)
    |> String.trim()
  end

  defp normalize_text(_), do: ""

  defp hash(binary), do: :sha256 |> :crypto.hash(binary) |> Base.encode16(case: :lower)

  defp message(payload) do
    cond do
      is_binary(payload["message"]) and payload["message"] != "" -> payload["message"]
      is_map(payload["message"]) -> payload["message"]["formatted"] || payload["message"]["message"]
      is_map(payload["logentry"]) -> payload["logentry"]["formatted"] || payload["logentry"]["message"]
      true -> nil
    end
  end

  # The Rust SDK's tracing integration emits events with no exception,
  # no frames and an empty message; the event's name lives here.
  defp tracing_name(payload) do
    case payload["contexts"] do
      %{"Rust Tracing Fields" => %{"name" => name}} -> presence(name)
      _ -> nil
    end
  end

  # Components reach the hash as strings, the way the ingest path
  # normalized them; reading decoded JSON as-is would hand a numeric
  # component to `Regex.match?/2`, which raises.
  defp fingerprint_override(fingerprint) when is_list(fingerprint),
    do: Enum.map(fingerprint, &to_string/1)

  defp fingerprint_override(_), do: nil

  # There is no exception type here by construction, so the title
  # falls through message, tracing event name and logger. `title` is
  # NOT NULL, and the live pipeline's last resort is the event id in
  # its 32-character form.
  defp title(%{message: message}, _id) when is_binary(message) and message != "", do: message
  defp title(%{tracing_name: name}, _id) when is_binary(name) and name != "", do: name
  defp title(%{logger: logger}, _id) when is_binary(logger) and logger != "", do: logger
  defp title(_event, event_id), do: "Event #{String.replace(event_id, "-", "")}"

  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_), do: nil

  defp decode(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp decode(_), do: %{}

  ## Accumulation

  # `vacated` records the fingerprints that lost events and `retained`
  # those that kept some; an issue is deleted only when it appears in
  # the first, not the second, and is not itself a destination.
  defp classify(row, state) do
    state = %{state | scanned: state.scanned + 1}

    if row.affected? do
      %{
        state
        | moved: state.moved + 1,
          groups: accumulate(state.groups, row),
          vacated: MapSet.put(state.vacated, key(row, row.fingerprint))
      }
    else
      %{state | retained: MapSet.put(state.retained, key(row, row.fingerprint))}
    end
  end

  defp key(row, fingerprint), do: {row.project_id, nullify(row.domain_id), fingerprint}

  # Rows arrive oldest-first, so the last row folded into a group is
  # its newest and supplies the metadata a freshly created issue gets.
  defp accumulate(groups, row) do
    entry = %{
      count: 1,
      first_seen: row.timestamp,
      last_seen: row.timestamp,
      title: row.title,
      culprit: row.culprit,
      level: row.level,
      platform: row.platform
    }

    Map.update(groups, key(row, row.corrected), entry, fn existing ->
      %{
        entry
        | count: existing.count + 1,
          first_seen: min_dt(existing.first_seen, row.timestamp),
          last_seen: max_dt(existing.last_seen, row.timestamp)
      }
    end)
  end

  ## ClickHouse rewrite

  # Issued per (origin, destination) pair, which keeps each delete
  # scoped by the fingerprint it targets. That is what stops the final
  # delete from removing the copies just written: a copy keeps the
  # original `event_id` and differs only by fingerprint.
  defp move([]), do: :ok

  defp move(rows) do
    rows
    |> Enum.group_by(&{&1.project_id, &1.domain_id, &1.fingerprint, &1.corrected})
    |> Enum.each(fn {{project_id, domain_id, from, to}, group} ->
      ids = Enum.map(group, & &1.event_id)

      delete_events(to, ids)
      copy_events(from, to, deterministic_id(project_id, nullify(domain_id), to), ids)
      delete_events(from, ids)
    end)
  end

  defp copy_events(from, to, issue_id, ids) do
    Hive.IngestRepo.query!(
      """
      INSERT INTO errors_events (issue_id, fingerprint, #{Enum.join(@carried, ", ")})
      SELECT {issue_id:String}, {to:FixedString(64)}, #{Enum.join(@carried, ", ")}
      FROM errors_events
      WHERE fingerprint = {from:FixedString(64)}
        AND event_id IN {ids:Array(UUID)}
      """,
      %{"issue_id" => issue_id, "to" => to, "from" => from, "ids" => ids}
    )
  end

  # `lightweight_deletes_sync` is pinned so the delete is visible
  # before the next statement runs — the copy and the delete that
  # follow both depend on seeing the table as this one left it.
  defp delete_events(fingerprint, ids) do
    Hive.IngestRepo.query!(
      """
      DELETE FROM errors_events
      WHERE fingerprint = {fingerprint:FixedString(64)}
        AND event_id IN {ids:Array(UUID)}
      SETTINGS lightweight_deletes_sync = 2
      """,
      %{"fingerprint" => fingerprint, "ids" => ids}
    )
  end

  ## Postgres issue rebuild

  defp upsert_issues(groups) when map_size(groups) == 0, do: 0

  defp upsert_issues(groups) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(groups, fn {{project_id, domain_id, fingerprint}, entry} ->
        %{
          id: dump_uuid(deterministic_id(project_id, domain_id, fingerprint)),
          project_id: dump_uuid(project_id),
          domain_id: dump_uuid(domain_id),
          fingerprint: fingerprint,
          title: truncate(entry.title),
          culprit: truncate(entry.culprit),
          level: level(entry.level),
          platform: entry.platform,
          status: "unresolved",
          first_seen: to_datetime(entry.first_seen),
          last_seen: to_datetime(entry.last_seen),
          event_count: entry.count,
          resolved_at: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    # Only the history widens. An existing row's events are newer than
    # anything refiled here, so its metadata and status stay untouched.
    on_conflict =
      from(existing in "errors_issues",
        update: [
          set: [
            event_count: fragment("? + EXCLUDED.event_count", existing.event_count),
            first_seen: fragment("LEAST(?, EXCLUDED.first_seen)", existing.first_seen),
            last_seen: fragment("GREATEST(?, EXCLUDED.last_seen)", existing.last_seen),
            updated_at: fragment("CURRENT_TIMESTAMP")
          ]
        ]
      )

    {count, _} =
      Hive.Repo.insert_all("errors_issues", rows,
        on_conflict: on_conflict,
        conflict_target: [:project_id, :domain_id, :fingerprint]
      )

    count
  end

  # Excludes the destinations as well as the retained fingerprints: a
  # fingerprint events left can also be one others arrived at, and
  # deleting it would drop a row written moments earlier.
  defp delete_emptied_issues(state) do
    state.vacated
    |> MapSet.difference(state.retained)
    |> MapSet.difference(MapSet.new(Map.keys(state.groups)))
    |> Enum.reduce(0, fn {project_id, domain_id, fingerprint}, acc ->
      {count, _} =
        "errors_issues"
        |> where(
          [i],
          i.project_id == type(^project_id, Ecto.UUID) and i.fingerprint == ^fingerprint
        )
        |> domain_scope(domain_id)
        |> Hive.Repo.delete_all()

      acc + count
    end)
  end

  defp domain_scope(query, nil), do: where(query, [i], is_nil(i.domain_id))

  defp domain_scope(query, domain_id),
    do: where(query, [i], i.domain_id == type(^domain_id, Ecto.UUID))

  ## Helpers

  # `mix ecto.migrate` starts `Hive.Repo` but not `Hive.IngestRepo`.
  # Tolerate it already running so this also works when co-run with the
  # application supervisor.
  defp ensure_ingest_repo do
    case Hive.IngestRepo.start_link() do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _} = error -> error
    end
  end

  # `insert_all` against a table name rather than a schema cannot infer
  # `binary_id` columns, so uuids are dumped by hand.
  defp dump_uuid(nil), do: nil
  defp dump_uuid(uuid), do: Ecto.UUID.dump!(uuid)

  # ClickHouse stores the project-level Data Source Name's domain as an
  # empty string; Postgres models it as NULL.
  defp nullify(""), do: nil
  defp nullify(value), do: value

  defp level(level) when is_binary(level), do: if(level in @levels, do: level, else: "error")
  defp level(_), do: "error"

  defp deterministic_id(project_id, nil, fingerprint),
    do: build_id(project_id <> ":" <> fingerprint)

  defp deterministic_id(project_id, domain_id, fingerprint),
    do: build_id(project_id <> ":" <> domain_id <> ":" <> fingerprint)

  defp build_id(name) do
    <<time_low::32, time_mid::16, _::4, time_hi::12, _::2, clock_hi::14, node::48, _rest::binary>> =
      :crypto.hash(:sha, @uuid_namespace <> name)

    Ecto.UUID.cast!(<<time_low::32, time_mid::16, 5::4, time_hi::12, 2::2, clock_hi::14, node::48>>)
  end

  # ClickHouse hands `DateTime64` back as a `NaiveDateTime`; the
  # `errors_issues` columns are `:utc_datetime_usec`.
  defp to_datetime(%NaiveDateTime{} = naive),
    do: naive |> DateTime.from_naive!("Etc/UTC") |> to_datetime()

  defp to_datetime(%DateTime{microsecond: {_, 6}} = dt), do: dt
  defp to_datetime(%DateTime{microsecond: {value, _}} = dt), do: %{dt | microsecond: {value, 6}}

  defp min_dt(a, b), do: if(compare(a, b) == :lt, do: a, else: b)
  defp max_dt(a, b), do: if(compare(a, b) == :gt, do: a, else: b)

  defp compare(%NaiveDateTime{} = a, %NaiveDateTime{} = b), do: NaiveDateTime.compare(a, b)
  defp compare(a, b), do: DateTime.compare(to_datetime(a), to_datetime(b))

  defp truncate(nil), do: nil
  defp truncate(binary), do: String.slice(binary, 0, 500)
end

defmodule Hive.Repo.DataMigrations.RegroupLiteralDefaultFingerprints do
  @moduledoc """
  Refiles error events that were grouped while the `{{ default }}`
  fingerprint token was hashed as literal text instead of expanded.

  An event's issue is decided once, when it is received, so correcting
  grouping only helped events that arrived afterwards. Everything
  already stored stayed under `sha256("{{ default }}")` — the hash the
  old code produced for every event from a Software Development Kit
  that sends `"fingerprint": ["{{ default }}"]`, which the Sentry Elixir
  one does on every event. On Tuist's instance that was 768 unrelated
  events sharing a single issue, titled after whichever event landed
  last.

  ## Why the grouping rules are copied in here

  This file does not call `Hive.Errors.Fingerprint` or
  `Hive.Errors.SentryEvent`, even though it reimplements a slice of
  both. A migration is permanent and the modules it would call are not:
  if grouping changes again, calling the live code would silently
  change what this migration does to instances that have not run it
  yet. The rules below are frozen as of the release that shipped the
  fix, and a future grouping change brings its own migration.
  `20260904150000_migrate_errors_issue_ids_to_deterministic.exs` copies
  the issue-id derivation for the same reason.

  ## What it touches

  Only events it can positively identify as victims of the bug: the
  stored payload carries a fingerprint array containing a default
  token, and hashing that array as literal text reproduces the
  fingerprint the row is stored under. Anything that fails either test
  is left alone, so an event grouped by some other rule cannot be
  swept up.

  `fingerprint` is part of `errors_events`' sorting key, so ClickHouse
  cannot mutate it in place — an event is copied to its corrected
  fingerprint and the original deleted. The copy is an
  `INSERT ... SELECT` so the 20-odd columns that keep their values are
  never decoded and re-encoded.

  Each group is cleared at its destination before being copied there.
  Dying between the copy and the delete would otherwise leave the event
  under both fingerprints, and the retry on the next deploy would copy
  it again.

  Issue rows only widen: counts add and first/last-seen stretch, while
  title, culprit, level, platform, status and assignee stay as the live
  pipeline left them, since refiled events are older than anything an
  existing issue holds. An issue whose events all moved away is
  deleted; one that kept any is left alone. Alert rules are not
  evaluated — this is history being filed correctly, not new activity.
  """
  use Ecto.Migration

  import Ecto.Query

  require Logger

  # The ClickHouse work is not transactional and the scan is long
  # enough that there is no reason to hold a Postgres transaction open
  # across it. The migration lock is deliberately left on: the chart
  # runs migrations from an init container on every pod, so above one
  # replica two of them start this at the same time, and without the
  # lock both would copy the same events.
  @disable_ddl_transaction true

  @batch_size 500

  # UUIDv5 namespace for issue ids, copied from
  # `Hive.Errors.Issue`. Frozen here on purpose — see the moduledoc.
  @uuid_namespace <<0x6F, 0x66, 0xEA, 0xF6, 0x2C, 0x18, 0x5C, 0x11, 0xA5, 0xB2, 0xD1, 0xF4, 0x5D,
                    0x8D, 0x22, 0x1A>>

  @default_token ~r/\A\{\{\s*default\s*\}\}\z/

  @levels ~w(fatal error warning info debug)

  # Every column carried across unchanged by the copy. `issue_id` and
  # `fingerprint`, the two being rewritten, are supplied as literals.
  @carried ~w(
    event_id project_id domain_id timestamp received_at platform level
    environment release dist server_name transaction logger exception_type
    exception_value top_frame_function top_frame_module top_frame_filename
    user_id user_email user_ip request_url request_method sdk_name sdk_version
    tags payload
  )

  def up do
    if Application.get_env(:hive, :clickhouse_enabled, false) do
      {:ok, _pid} = ensure_ingest_repo()
      Logger.info("errors: refiling events grouped under a literal default fingerprint")
      Logger.info("errors: refiled #{inspect(run(DateTime.utc_now()))}")
    end

    :ok
  end

  # Irreversible: the superseded fingerprint described a grouping that
  # no longer exists, so there is nothing correct to restore.
  def down, do: :ok

  @doc """
  Refiles every affected event at or before `cutoff` and rebuilds the
  issues involved. `cutoff` bounds a scan of a table that is still
  being written to; events arriving after it were grouped correctly.

  Public so the grouping decisions can be exercised by tests.
  """
  def run(cutoff, batch_size \\ @batch_size) do
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

  # Only what is needed to re-derive a fingerprint and rebuild an issue
  # row. `event_id` is read as text so it can be handed back as an
  # `Array(UUID)` parameter without round-tripping raw bytes.
  defp read_batch(cutoff, batch_size, cursor) do
    {keyset, params} = keyset(cursor)

    %{rows: rows} =
      Hive.IngestRepo.query!(
        """
        SELECT toString(event_id), project_id, domain_id, fingerprint,
               timestamp, level, platform, payload
        FROM errors_events
        WHERE timestamp <= {cutoff:DateTime64(6)}#{keyset}
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

  ## Grouping rules, frozen as of the release that fixed them

  @doc """
  Decides whether one stored row was grouped by the literal-token bug
  and, if so, what its fingerprint should have been.

  Takes the row as `read_batch/3` selects it. Public for tests.
  """
  def decorate([event_id, project_id, domain_id, fingerprint, ts, level, platform, payload]) do
    event = payload |> decode() |> parse()
    override = event.fingerprint

    # The row is only touched when hashing its fingerprint array as
    # literal text reproduces the fingerprint it is stored under. That
    # is the signature of the old code, and it is what makes this safe
    # to run over a table holding events grouped by other rules.
    affected? =
      is_list(override) and Enum.any?(override, &default_token?/1) and
        hash(Enum.join(override, "|")) == fingerprint

    %{
      event_id: event_id,
      project_id: project_id,
      domain_id: domain_id,
      fingerprint: fingerprint,
      timestamp: ts,
      level: level,
      platform: platform,
      title: title(event, event_id),
      culprit: culprit(event),
      affected?: affected?,
      corrected: affected? && corrected_fingerprint(override, event)
    }
  end

  defp corrected_fingerprint(override, event) do
    override
    |> Enum.flat_map(fn component ->
      if default_token?(component), do: default_components(event), else: [component]
    end)
    |> Enum.join("|")
    |> hash()
  end

  defp default_token?(component), do: Regex.match?(@default_token, component)

  defp default_components(event) do
    {function, location} =
      case event.top_frame do
        nil -> {"", ""}
        frame -> {frame["function"] || "", frame["module"] || frame["filename"] || ""}
      end

    [event.type || "", function, location, normalize_message(event.message || event.value || "")]
  end

  defp normalize_message(binary) when is_binary(binary) do
    binary
    |> String.replace(~r/0x[0-9a-fA-F]+/, "0x*")
    |> String.replace(~r/\d+/, "N")
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 200)
    |> String.trim()
  end

  defp normalize_message(_), do: ""

  defp hash(binary), do: :sha256 |> :crypto.hash(binary) |> Base.encode16(case: :lower)

  # The slice of Sentry event parsing these rules depend on.
  defp parse(payload) do
    {type, value, frames} = first_exception(payload)

    %{
      type: type,
      value: value,
      top_frame: top_frame(frames),
      message: message(payload),
      fingerprint: payload["fingerprint"]
    }
  end

  defp first_exception(payload) do
    values =
      case payload["exception"] do
        %{"values" => values} when is_list(values) -> values
        values when is_list(values) -> values
        _ -> []
      end

    case values do
      [%{} = first | _] ->
        frames =
          case first["stacktrace"] do
            %{"frames" => frames} when is_list(frames) -> frames
            _ -> []
          end

        {presence(first["type"]), presence(first["value"]), frames}

      _ ->
        {nil, nil, []}
    end
  end

  defp top_frame([]), do: nil

  defp top_frame(frames) do
    case frames |> Enum.filter(&match?(%{"in_app" => true}, &1)) |> Enum.reverse() do
      [frame | _] -> frame
      [] -> List.last(frames)
    end
  end

  defp message(payload) do
    cond do
      is_binary(payload["message"]) and payload["message"] != "" ->
        payload["message"]

      is_map(payload["message"]) ->
        payload["message"]["formatted"] || payload["message"]["message"]

      is_map(payload["logentry"]) ->
        payload["logentry"]["formatted"] || payload["logentry"]["message"]

      true ->
        nil
    end
  end

  defp title(%{type: type, value: value}, _event_id) when is_binary(type) do
    if is_binary(value) and value != "", do: "#{type}: #{value}", else: type
  end

  defp title(%{message: message}, _event_id) when is_binary(message) and message != "",
    do: message

  # `errors_issues.title` is NOT NULL, and the live pipeline falls back
  # to the event id in its 32-character form.
  defp title(_event, event_id), do: "Event #{String.replace(event_id, "-", "")}"

  defp culprit(%{top_frame: nil}), do: nil

  defp culprit(%{top_frame: frame}) do
    location =
      case {frame["filename"] || frame["abs_path"], frame["lineno"]} do
        {name, line} when is_binary(name) and not is_nil(line) -> "#{name}:#{line}"
        {name, _} when is_binary(name) -> name
        _ -> nil
      end

    case Enum.filter([frame["function"] || frame["module"], location], &presence/1) do
      [] -> nil
      parts -> Enum.join(parts, " at ")
    end
  end

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
  # the first and not the second.
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
  # its newest and supplies the metadata a freshly created issue gets —
  # the same last-writer-wins rule the live pipeline applies.
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

  defp delete_emptied_issues(state) do
    state.vacated
    |> MapSet.difference(state.retained)
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
  # `binary_id` columns, so uuids are dumped by hand — the same thing
  # `20260904150000_migrate_errors_issue_ids_to_deterministic.exs` does.
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

    Ecto.UUID.cast!(
      <<time_low::32, time_mid::16, 5::4, time_hi::12, 2::2, clock_hi::14, node::48>>
    )
  end

  # ClickHouse hands `DateTime64` back as a `NaiveDateTime`; the
  # `errors_issues` columns are `:utc_datetime_usec` and demand
  # precision 6.
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

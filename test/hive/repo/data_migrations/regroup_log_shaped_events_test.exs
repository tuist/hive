defmodule Hive.Repo.DataMigrations.RegroupLogShapedEventsTest do
  @moduledoc """
  Covers the grouping rules the data migration froze into itself.

  The migration reimplements a slice of `Hive.Errors.Fingerprint` and
  `Hive.Errors.SentryEvent` deliberately, so a later grouping change
  cannot alter what it does. These tests pin the copy to the behaviour
  it was frozen from: they assert it agrees with the live modules
  *today*, which is the only moment the two are meant to match.
  """
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Errors.Fingerprint
  alias Hive.Errors.Issue
  alias Hive.Errors.SentryEvent
  alias Hive.Projects
  alias Hive.Repo

  @migration Hive.Repo.DataMigrations.RegroupLogShapedEvents

  unless Code.ensure_loaded?(@migration) do
    Code.require_file("priv/repo/migrations/20260910160000_regroup_log_shaped_events.exs")
  end

  # What every log-shaped event hashed to before grouping had a
  # fallback: four blank components joined by three separators.
  @catch_all :sha256 |> :crypto.hash("|||") |> Base.encode16(case: :lower)

  setup do
    {:ok, project} =
      Projects.create_project(%{"name" => "logshaped-#{System.unique_integer([:positive])}"})

    {:ok, project: project}
  end

  describe "decorate/1 agreement with live grouping" do
    test "derives the fingerprint live grouping now gives the event", %{project: project} do
      payload = otel_payload()

      row = @migration.decorate(row(project, payload, logger: "opentelemetry_sdk"))

      assert row.affected?
      assert row.corrected == Fingerprint.compute(parsed(payload, logger: "opentelemetry_sdk"))
      refute row.corrected == @catch_all
    end

    test "derives the title and culprit live grouping gives it", %{project: project} do
      payload = otel_payload()
      parsed = parsed(payload, logger: "opentelemetry_sdk", transaction: "export/1")

      row =
        @migration.decorate(
          row(project, payload, logger: "opentelemetry_sdk", transaction: "export/1")
        )

      assert row.title == SentryEvent.title(parsed)
      assert row.title == "BatchSpanProcessor.ExportError"
      assert row.culprit == SentryEvent.culprit(parsed)
      assert row.culprit == "export/1"
    end

    test "separates events that differ only by logger", %{project: project} do
      payload = %{"platform" => "native", "message" => ""}

      a = @migration.decorate(row(project, payload, logger: "worker.a"))
      b = @migration.decorate(row(project, payload, logger: "worker.b"))

      assert a.affected? and b.affected?
      refute a.corrected == b.corrected
    end

    test "collapses transactions that differ only by record id", %{project: project} do
      payload = %{"platform" => "native", "message" => ""}

      a = @migration.decorate(row(project, payload, logger: "web", transaction: "GET /users/1"))
      b = @migration.decorate(row(project, payload, logger: "web", transaction: "GET /users/999"))

      assert a.corrected == b.corrected
    end

    test "expands the token in place inside a composite fingerprint", %{project: project} do
      payload = otel_payload() |> Map.put("fingerprint", ["kura", "{{ default }}"])
      stale = hash("kura||||")

      row =
        @migration.decorate(
          row(project, payload, fingerprint: stale, logger: "opentelemetry_sdk")
        )

      assert row.affected?
      assert row.corrected == Fingerprint.compute(parsed(payload, logger: "opentelemetry_sdk"))
    end
  end

  describe "decorate/1 leaving unaffected rows alone" do
    test "ignores an event whose message gives it something to group on", %{project: project} do
      payload = %{"platform" => "native", "message" => "failed to send batch"}

      refute @migration.decorate(row(project, payload, logger: "kura")).affected?
    end

    # The signature is that the old rules reproduce what is stored.
    # Without it, an event already grouped on its identity would be
    # moved a second time.
    test "ignores an event already grouped on its identity", %{project: project} do
      payload = otel_payload()
      correct = Fingerprint.compute(parsed(payload, logger: "opentelemetry_sdk"))

      row =
        @migration.decorate(
          row(project, payload, fingerprint: correct, logger: "opentelemetry_sdk")
        )

      refute row.affected?
    end

    test "ignores a deliberate literal fingerprint with no token", %{project: project} do
      payload = otel_payload() |> Map.put("fingerprint", ["kura-telemetry"])

      row =
        @migration.decorate(
          row(project, payload, fingerprint: hash("kura-telemetry"), logger: "opentelemetry_sdk")
        )

      refute row.affected?
    end

    # An event with no identity at all still reduces to four blanks
    # under the new rules, so there is nowhere to move it.
    test "ignores an event with no identity to fall back on", %{project: project} do
      row =
        @migration.decorate(row(project, %{"platform" => "native", "message" => ""}, level: ""))

      refute row.affected?
    end

    # The live parser collapses an empty array to nil, so such an
    # event grouped through the default path and is refilable like any
    # other. Treating [] as a literal array would strand it.
    test "refiles an event sent with an empty fingerprint array", %{project: project} do
      payload = otel_payload() |> Map.put("fingerprint", [])

      row = @migration.decorate(row(project, payload, logger: "opentelemetry_sdk"))

      assert row.affected?
      assert row.corrected == Fingerprint.compute(parsed(payload, logger: "opentelemetry_sdk"))
    end

    # A stored payload is always valid JSON — ingest decoded it before
    # writing the row — but the decision must not raise if one is not,
    # and it should land where live grouping would put an event whose
    # payload carries nothing.
    test "falls back to the columns on an unparseable payload", %{project: project} do
      row = @migration.decorate(raw_row(project, "not json"))

      live =
        Fingerprint.compute(%{
          SentryEvent.parse(%{})
          | logger: "",
            transaction: "",
            level: "error"
        })

      assert row.corrected == live
    end
  end

  describe "up/0" do
    # `Hive.IngestRepo` is only configured when ClickHouse is enabled,
    # so touching it unconditionally aborts the migration — and the
    # deploy — on instances running without it. The test environment
    # is one of them.
    test "does not touch ClickHouse when it is disabled" do
      refute Application.get_env(:hive, :clickhouse_enabled, false)
      reject(&Hive.IngestRepo.query!/2)

      assert @migration.up() == :ok
    end
  end

  describe "run/2" do
    test "joins the stranded history onto the issue its identity resolves to", %{project: project} do
      payload = otel_payload()
      destination = Fingerprint.compute(parsed(payload, logger: "opentelemetry_sdk"))

      seed_issue(project, @catch_all, "Event c59fc1e90e95410caf49f94912c45fd2", 247)

      stub_clickhouse([
        [
          row(project, payload, logger: "opentelemetry_sdk"),
          row(project, payload, logger: "opentelemetry_sdk")
        ]
      ])

      report = @migration.run(DateTime.utc_now())

      assert report.scanned == 2
      assert report.moved == 2
      assert report.issues_written == 1
      assert report.issues_deleted == 1

      issue = Repo.get_by!(Issue, project_id: project.id, fingerprint: destination)
      assert issue.id == Issue.deterministic_id(project.id, nil, destination)
      assert issue.title == "BatchSpanProcessor.ExportError"
      assert issue.event_count == 2

      refute Repo.get_by(Issue, project_id: project.id, fingerprint: @catch_all)
    end

    test "widens an issue that already exists without rewriting its metadata", %{project: project} do
      payload = otel_payload()
      destination = Fingerprint.compute(parsed(payload, logger: "opentelemetry_sdk"))
      seen = ~U[2026-09-10 14:00:00.000000Z]
      refiled_at = ~N[2026-09-07 17:08:25.030462]

      issue =
        seed_issue(project, destination, "BatchSpanProcessor.ExportError", 5, last_seen: seen)

      stub_clickhouse([
        [row(project, payload, logger: "opentelemetry_sdk", timestamp: refiled_at)]
      ])

      @migration.run(DateTime.utc_now())

      reloaded = Repo.get!(Issue, issue.id)

      assert reloaded.event_count == 6
      assert reloaded.first_seen == DateTime.from_naive!(refiled_at, "Etc/UTC")
      assert reloaded.last_seen == seen
      assert reloaded.title == "BatchSpanProcessor.ExportError"
    end

    test "clears the destination, copies, then drops the originals", %{project: project} do
      payload = otel_payload()
      destination = Fingerprint.compute(parsed(payload, logger: "opentelemetry_sdk"))

      stub_clickhouse([[row(project, payload, logger: "opentelemetry_sdk")]])

      @migration.run(DateTime.utc_now())

      assert_receive {:write, clear, %{"fingerprint" => ^destination}}
      assert clear =~ "DELETE FROM errors_events"

      assert_receive {:write, copy, copy_params}
      assert copy =~ "INSERT INTO errors_events"
      assert copy_params["to"] == destination
      assert copy_params["from"] == @catch_all

      assert_receive {:write, drop, %{"fingerprint" => @catch_all}}
      assert drop =~ "DELETE FROM errors_events"
    end

    test "reads only log-shaped rows", %{project: project} do
      stub_clickhouse([[row(project, otel_payload(), logger: "opentelemetry_sdk")]])

      @migration.run(DateTime.utc_now())

      assert_receive {:read_sql, sql}
      assert sql =~ "exception_type = ''"
      assert sql =~ "exception_value = ''"
      assert sql =~ "top_frame_function = ''"
      assert sql =~ "top_frame_module = ''"
      assert sql =~ "top_frame_filename = ''"
    end

    # The scan only reads log-shaped rows, so a fingerprint can still
    # hold events it never saw. Deleting its issue would leave those
    # events pointing at a row that no longer exists.
    test "keeps an issue while ClickHouse still holds events at its fingerprint", %{
      project: project
    } do
      payload = otel_payload()
      issue = seed_issue(project, @catch_all, "Event c59fc1e9", 3)

      stub_clickhouse([[row(project, payload, logger: "opentelemetry_sdk")]],
        remaining_at_origin: 1
      )

      report = @migration.run(DateTime.utc_now())

      assert report.moved == 1
      assert report.issues_deleted == 0
      assert Repo.get!(Issue, issue.id)
    end

    test "does nothing before the events table exists" do
      stub(Hive.IngestRepo, :query!, fn
        "EXISTS TABLE errors_events", _ -> %{rows: [[0]]}
        sql, _ -> raise "should not have queried: #{sql}"
      end)

      assert @migration.run(DateTime.utc_now()) == %{
               scanned: 0,
               moved: 0,
               issues_written: 0,
               issues_deleted: 0
             }
    end
  end

  ## Helpers

  defp stub_clickhouse(batches, opts \\ []) do
    agent = start_supervised!({Agent, fn -> batches end})
    remaining = Keyword.get(opts, :remaining_at_origin, 0)
    test_pid = self()

    stub(Hive.IngestRepo, :query!, fn sql, params ->
      cond do
        String.starts_with?(sql, "EXISTS TABLE") ->
          %{rows: [[1]]}

        String.starts_with?(sql, "SELECT count()") ->
          %{rows: [[remaining]]}

        String.starts_with?(sql, "SELECT") ->
          send(test_pid, {:read, params})
          send(test_pid, {:read_sql, sql})

          rows =
            Agent.get_and_update(agent, fn
              [] -> {[], []}
              [head | tail] -> {head, tail}
            end)

          %{rows: rows}

        true ->
          send(test_pid, {:write, sql, params})
          %{rows: []}
      end
    end)
  end

  defp hash(binary), do: :sha256 |> :crypto.hash(binary) |> Base.encode16(case: :lower)

  defp otel_payload do
    %{
      "platform" => "native",
      "message" => "",
      "contexts" => %{
        "Rust Tracing Fields" => %{"name" => "BatchSpanProcessor.ExportError"}
      }
    }
  end

  # The live struct as ingest would have built it: logger and
  # transaction are columns on the stored row, so mirror them onto the
  # parsed event before comparing.
  defp parsed(payload, opts) do
    %{
      SentryEvent.parse(payload)
      | logger: Keyword.get(opts, :logger),
        transaction: Keyword.get(opts, :transaction)
    }
  end

  defp row(project, payload, opts) do
    [
      Keyword.get(opts, :event_id, Ecto.UUID.generate()),
      project.id,
      Keyword.get(opts, :domain_id, ""),
      Keyword.get(opts, :fingerprint, @catch_all),
      Keyword.get(opts, :timestamp, ~N[2026-09-07 17:08:25.030462]),
      Keyword.get(opts, :level, "error"),
      Keyword.get(opts, :platform, "native"),
      Keyword.get(opts, :logger, ""),
      Keyword.get(opts, :transaction, ""),
      Jason.encode!(payload)
    ]
  end

  defp raw_row(project, payload) do
    [
      Ecto.UUID.generate(),
      project.id,
      "",
      @catch_all,
      ~N[2026-09-07 17:08:25.030462],
      "error",
      "native",
      "",
      "",
      payload
    ]
  end

  defp seed_issue(project, fingerprint, title, event_count, opts \\ []) do
    seen = ~U[2026-09-07 17:08:25.030462Z]

    {:ok, issue} =
      %Issue{}
      |> Issue.changeset(%{
        project_id: project.id,
        fingerprint: fingerprint,
        title: title,
        culprit: nil,
        level: :error,
        platform: "native",
        first_seen: Keyword.get(opts, :first_seen, seen),
        last_seen: Keyword.get(opts, :last_seen, seen),
        event_count: event_count
      })
      |> Repo.insert()

    issue
  end
end

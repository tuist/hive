defmodule Hive.Repo.DataMigrations.RegroupLiteralDefaultFingerprintsTest do
  @moduledoc """
  Covers the grouping rules the data migration froze into itself.

  The migration reimplements a slice of `Hive.Errors.Fingerprint` and
  `Hive.Errors.SentryEvent` on purpose, so that a later grouping change
  cannot alter what it does. These tests pin the copy to the behaviour
  it was frozen from: they assert the migration agrees with the live
  modules *today*, which is the only moment the two are meant to match.
  """
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Errors.Fingerprint
  alias Hive.Errors.Issue
  alias Hive.Errors.SentryEvent
  alias Hive.Projects
  alias Hive.Repo

  @migration Hive.Repo.DataMigrations.RegroupLiteralDefaultFingerprints

  # `mix test` runs `ecto.migrate` first, which compiles the migration
  # into the VM. Require the file only when it isn't already loaded, so
  # the module is never redefined.
  unless Code.ensure_loaded?(@migration) do
    Code.require_file(
      "priv/repo/migrations/20260910090000_regroup_literal_default_fingerprints.exs"
    )
  end

  # The hash the old code produced for every event whose Software
  # Development Kit sent `"fingerprint": ["{{ default }}"]`.
  @stale :sha256 |> :crypto.hash("{{ default }}") |> Base.encode16(case: :lower)

  setup do
    {:ok, project} =
      Projects.create_project(%{"name" => "regroup-#{System.unique_integer([:positive])}"})

    {:ok, project: project}
  end

  describe "decorate/1 agreement with live grouping" do
    test "derives the fingerprint the live code would compute", %{project: project} do
      for payload <- [
            exception_payload("RuntimeError", "kaboom", "boom/0", "lib/x.ex"),
            exception_payload("Jason.EncodeError", "invalid byte 0xA0", "encode!/2", "lib/j.ex"),
            exception_payload("MatchError", "no match of right hand side", "run/3", "lib/s3.ex")
          ] do
        row = @migration.decorate(row(project, payload, fingerprint: @stale))

        assert row.affected?
        assert row.corrected == Fingerprint.compute(SentryEvent.parse(payload))
      end
    end

    test "derives the title and culprit the live code would", %{project: project} do
      payload = exception_payload("RuntimeError", "kaboom", "boom/0", "lib/x.ex")
      parsed = SentryEvent.parse(payload)

      row = @migration.decorate(row(project, payload, fingerprint: @stale))

      assert row.title == SentryEvent.title(parsed)
      assert row.culprit == SentryEvent.culprit(parsed)
    end

    test "expands the token in place inside a composite fingerprint", %{project: project} do
      payload =
        "RuntimeError"
        |> exception_payload("kaboom", "boom/0", "lib/x.ex")
        |> Map.put("fingerprint", ["build-worker", "{{ default }}"])

      stale = hash("build-worker|{{ default }}")
      row = @migration.decorate(row(project, payload, fingerprint: stale))

      assert row.affected?
      assert row.corrected == Fingerprint.compute(SentryEvent.parse(payload))
    end

    test "recognizes the token's accepted spellings", %{project: project} do
      for token <- ["{{ default }}", "{{default}}", "{{  default  }}"] do
        payload =
          "RuntimeError"
          |> exception_payload("kaboom", "boom/0", "lib/x.ex")
          |> Map.put("fingerprint", [token])

        row = @migration.decorate(row(project, payload, fingerprint: hash(token)))

        assert row.affected?, "expected #{token} to be recognized"
        assert row.corrected == Fingerprint.compute(SentryEvent.parse(payload))
      end
    end
  end

  describe "decorate/1 leaving unaffected rows alone" do
    test "ignores an event with no fingerprint array", %{project: project} do
      payload =
        "RuntimeError"
        |> exception_payload("kaboom", "boom/0", "lib/x.ex")
        |> Map.delete("fingerprint")

      refute @migration.decorate(row(project, payload, fingerprint: @stale)).affected?
    end

    test "ignores a deliberate literal fingerprint with no token", %{project: project} do
      payload =
        "RuntimeError"
        |> exception_payload("kaboom", "boom/0", "lib/x.ex")
        |> Map.put("fingerprint", ["build-worker"])

      row = @migration.decorate(row(project, payload, fingerprint: hash("build-worker")))
      refute row.affected?
    end

    # The signature of the bug is that hashing the array as literal text
    # reproduces the stored fingerprint. Without this guard, an event
    # already grouped correctly would be moved a second time.
    test "ignores a token-bearing event already grouped correctly", %{project: project} do
      payload = exception_payload("RuntimeError", "kaboom", "boom/0", "lib/x.ex")
      correct = Fingerprint.compute(SentryEvent.parse(payload))

      refute @migration.decorate(row(project, payload, fingerprint: correct)).affected?
    end

    # The live ingest path stores these fine because it runs the array
    # through `to_string/1` before matching, so the migration has to
    # too or it raises on the first numeric component it meets.
    test "handles a non-string component in the fingerprint array", %{project: project} do
      payload =
        "RuntimeError"
        |> exception_payload("kaboom", "boom/0", "lib/x.ex")
        |> Map.put("fingerprint", [12_345, "{{ default }}"])

      row = @migration.decorate(row(project, payload, fingerprint: hash("12345|{{ default }}")))

      assert row.affected?
      assert row.corrected == Fingerprint.compute(SentryEvent.parse(payload))
    end

    test "ignores an unparseable payload", %{project: project} do
      row = @migration.decorate(row_with_payload(project, "not json", @stale))
      refute row.affected?
    end
  end

  # `Hive.Release.migrate` runs the Postgres migrations before the
  # ClickHouse ones that create the events table, so on a first install
  # this migration runs against a table that does not exist yet.
  describe "run/2 before the events table exists" do
    test "does nothing instead of aborting the migration" do
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

  describe "run/2" do
    test "splits unrelated exceptions into their own issues", %{project: project} do
      jason = exception_payload("Jason.EncodeError", "invalid byte 0xA0", "encode!/2", "lib/j.ex")
      match = exception_payload("MatchError", "no match of right hand side", "run/3", "lib/s3.ex")

      seed_issue(project, @stale, "MatchError: no match of right hand side", 768)

      stub_clickhouse([
        [row(project, jason, fingerprint: @stale), row(project, match, fingerprint: @stale)]
      ])

      report = @migration.run(DateTime.utc_now())

      assert report.scanned == 2
      assert report.moved == 2
      assert report.issues_written == 2
      assert report.issues_deleted == 1

      titles = project |> issues_for() |> Enum.map(& &1.title) |> Enum.sort()

      assert titles == [
               "Jason.EncodeError: invalid byte 0xA0",
               "MatchError: no match of right hand side"
             ]

      refute Repo.get_by(Issue, project_id: project.id, fingerprint: @stale)
    end

    test "files each event under the issue id its fingerprint resolves to", %{project: project} do
      payload = exception_payload("RuntimeError", "kaboom", "boom/0", "lib/x.ex")
      expected = Fingerprint.compute(SentryEvent.parse(payload))

      stub_clickhouse([[row(project, payload, fingerprint: @stale)]])

      @migration.run(DateTime.utc_now())

      issue = Repo.get_by!(Issue, project_id: project.id, fingerprint: expected)
      assert issue.id == Issue.deterministic_id(project.id, nil, expected)
      assert issue.event_count == 1
      assert issue.culprit == "boom/0 at lib/x.ex:1"
      assert issue.status == :unresolved
    end

    test "clears the destination, copies, then drops the originals", %{project: project} do
      payload = exception_payload("RuntimeError", "kaboom", "boom/0", "lib/x.ex")
      expected = Fingerprint.compute(SentryEvent.parse(payload))

      stub_clickhouse([[row(project, payload, fingerprint: @stale)]])

      @migration.run(DateTime.utc_now())

      # Clearing first is what lets a migration that died between the
      # copy and the drop be retried without duplicating the event.
      assert_receive {:write, clear, %{"fingerprint" => ^expected}}
      assert clear =~ "DELETE FROM errors_events"

      assert_receive {:write, copy, copy_params}
      assert copy =~ "INSERT INTO errors_events"
      assert copy_params["to"] == expected
      assert copy_params["from"] == @stale

      assert_receive {:write, drop, %{"fingerprint" => @stale}}
      assert drop =~ "DELETE FROM errors_events"
    end

    test "leaves an issue in place when it keeps some of its events", %{project: project} do
      affected = exception_payload("RuntimeError", "kaboom", "boom/0", "lib/x.ex")

      unaffected =
        "StayPut"
        |> exception_payload("unchanged", "stay/0", "lib/stay.ex")
        |> Map.put("fingerprint", ["build-worker"])

      shared = hash("{{ default }}")
      issue = seed_issue(project, shared, "MatchError: something", 3)

      stub_clickhouse([
        [
          row(project, affected, fingerprint: shared),
          row(project, unaffected, fingerprint: shared)
        ]
      ])

      report = @migration.run(DateTime.utc_now())

      assert report.moved == 1
      assert report.issues_deleted == 0
      assert Repo.get!(Issue, issue.id).title == "MatchError: something"
    end

    test "widens an existing issue without rewriting its live metadata", %{project: project} do
      payload = exception_payload("RuntimeError", "kaboom", "boom/0", "lib/x.ex")
      fingerprint = Fingerprint.compute(SentryEvent.parse(payload))
      seen = ~U[2026-09-09 15:00:00.000000Z]
      refiled_at = ~N[2026-09-04 22:03:34.335295]

      issue =
        seed_issue(project, fingerprint, "title set by the live pipeline", 5,
          first_seen: seen,
          last_seen: seen,
          culprit: "culprit set by the live pipeline"
        )

      stub_clickhouse([[row(project, payload, fingerprint: @stale, timestamp: refiled_at)]])

      @migration.run(DateTime.utc_now())

      reloaded = Repo.get!(Issue, issue.id)

      assert reloaded.event_count == 6
      assert reloaded.first_seen == DateTime.from_naive!(refiled_at, "Etc/UTC")
      assert reloaded.last_seen == seen
      assert reloaded.title == "title set by the live pipeline"
      assert reloaded.culprit == "culprit set by the live pipeline"
    end

    # A fingerprint that events left can also be one that other events
    # arrived at. Deleting it would drop an issue row written moments
    # earlier and orphan the events now pointing at it.
    #
    # Reaching that state takes a contrived pair, because a
    # destination is a hash of expanded components and a vacated
    # fingerprint is a hash of a literal array: they can only coincide
    # when one event's components are exactly another event's
    # fingerprint array. An exception whose message is itself the
    # token is the shortest way there.
    test "keeps an issue whose fingerprint is also a destination", %{project: project} do
      arriving = exception_payload("A", "{{ default }}", "f/0", "lib/a.ex")
      components = ["A", "f/0", "Elixir.Example", "{{ default }}"]
      destination = hash(Enum.join(components, "|"))

      assert destination == Fingerprint.compute(SentryEvent.parse(arriving))

      departing =
        "B"
        |> exception_payload("b", "g/0", "lib/b.ex")
        |> Map.put("fingerprint", components)

      seed_issue(project, destination, "stale", 1)

      stub_clickhouse([
        [
          row(project, arriving, fingerprint: @stale),
          row(project, departing, fingerprint: destination)
        ]
      ])

      report = @migration.run(DateTime.utc_now())

      assert report.moved == 2
      assert report.issues_deleted == 0
      assert Repo.get_by!(Issue, project_id: project.id, fingerprint: destination)
    end

    test "pages with a keyset cursor rather than re-reading from the start", %{project: project} do
      first = exception_payload("RuntimeError", "one", "boom/0", "lib/x.ex")
      second = exception_payload("ArgumentError", "two", "bang/0", "lib/y.ex")
      later = ~N[2026-09-05 10:00:00.000000]

      stub_clickhouse([
        [row(project, first, fingerprint: @stale)],
        [row(project, second, fingerprint: @stale, timestamp: later)],
        []
      ])

      report = @migration.run(DateTime.utc_now(), 1)

      assert report.scanned == 2
      assert report.moved == 2
      assert report.issues_written == 2

      assert_receive {:read, first_params}
      refute Map.has_key?(first_params, "after_ts")

      assert_receive {:read, second_params}
      assert Map.has_key?(second_params, "after_ts")

      assert_receive {:read, third_params}
      assert third_params["after_ts"] == later
    end
  end

  ## Helpers

  # Reads and writes both go through `Hive.IngestRepo.query!/2`, so the
  # stub tells them apart by statement and serves the given batches to
  # successive reads.
  defp stub_clickhouse(batches) do
    agent = start_supervised!({Agent, fn -> batches end})
    test_pid = self()

    stub(Hive.IngestRepo, :query!, fn sql, params ->
      cond do
        String.starts_with?(sql, "EXISTS TABLE") ->
          %{rows: [[1]]}

        String.starts_with?(sql, "SELECT") ->
          send(test_pid, {:read, params})

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

  defp exception_payload(type, value, function, filename) do
    %{
      "fingerprint" => ["{{ default }}"],
      "exception" => [
        %{
          "type" => type,
          "value" => value,
          "stacktrace" => %{
            "frames" => [
              %{
                "function" => function,
                "filename" => filename,
                "module" => "Elixir.Example",
                "lineno" => 1,
                "in_app" => false
              }
            ]
          }
        }
      ]
    }
  end

  # One row in the shape the migration's SELECT returns.
  defp row(project, payload, opts) do
    [
      Keyword.get(opts, :event_id, Ecto.UUID.generate()),
      project.id,
      Keyword.get(opts, :domain_id, ""),
      Keyword.fetch!(opts, :fingerprint),
      Keyword.get(opts, :timestamp, ~N[2026-09-04 22:03:34.335295]),
      Keyword.get(opts, :level, "error"),
      Keyword.get(opts, :platform, "elixir"),
      Jason.encode!(payload)
    ]
  end

  defp row_with_payload(project, payload, fingerprint) do
    [
      Ecto.UUID.generate(),
      project.id,
      "",
      fingerprint,
      ~N[2026-09-04 22:03:34.335295],
      "error",
      "elixir",
      payload
    ]
  end

  defp seed_issue(project, fingerprint, title, event_count, opts \\ []) do
    seen = ~U[2026-09-04 22:03:34.335295Z]

    {:ok, issue} =
      %Issue{}
      |> Issue.changeset(%{
        project_id: project.id,
        fingerprint: fingerprint,
        title: title,
        culprit: Keyword.get(opts, :culprit, "somewhere"),
        level: :error,
        platform: "elixir",
        first_seen: Keyword.get(opts, :first_seen, seen),
        last_seen: Keyword.get(opts, :last_seen, seen),
        event_count: event_count
      })
      |> Repo.insert()

    issue
  end

  defp issues_for(project) do
    Issue |> where([i], i.project_id == ^project.id) |> Repo.all()
  end
end

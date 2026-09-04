defmodule Hive.ErrorsHelpers do
  @moduledoc """
  Test helpers for the `Hive.Errors` context.

  Production ingest is asynchronous — `Hive.Errors.record_event/2`
  casts to `Hive.Errors.Event.Buffer` and `Hive.Errors.IssueCoalescer`
  and returns immediately, so the issue row is not visible in Postgres
  until the coalescer's next flush. Tests that need an issue row to
  exist synchronously can use `seed_issue/2` to write one directly.
  """

  alias Hive.Errors.Fingerprint
  alias Hive.Errors.Issue
  alias Hive.Errors.SentryEvent
  alias Hive.Repo

  @doc """
  Creates and returns a persisted `Hive.Errors.Issue` for the given
  project and Sentry event. The id is the deterministic UUIDv5 that
  `Hive.Errors.IssueCoalescer` would compute, so lookups by
  `Issue.deterministic_id/2` are stable across seed and coalescer
  paths.
  """
  def seed_issue(project, %SentryEvent{} = event) do
    fingerprint = Fingerprint.compute(event)
    now = event.timestamp || DateTime.utc_now()

    attrs = %{
      project_id: project.id,
      fingerprint: fingerprint,
      title: SentryEvent.title(event),
      culprit: SentryEvent.culprit(event),
      level: String.to_atom(event.level),
      platform: event.platform,
      first_seen: now,
      last_seen: now,
      event_count: 1
    }

    %Issue{}
    |> Issue.changeset(attrs)
    |> Repo.insert()
  end
end

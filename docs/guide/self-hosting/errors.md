# Errors

Hive captures unhandled exceptions from applications through a
Sentry-compatible ingest endpoint and stores them in the instance for
later review. The same pipeline records Hive's own crashes against a
private "Hive" project so operators can investigate the tool itself
without a second observability system.

## Availability

Error tracking is available when
[ClickHouse](/reference/configuration#hive_clickhouse_enabled) is
enabled. ClickHouse holds the append-only event stream; PostgreSQL
holds the grouped issues, statuses, and Data Source Name credentials.
Leaving ClickHouse disabled turns the ingest endpoint off; nothing
else in Hive is affected.

## Privacy

Error events routinely carry sensitive data — user identifiers,
request payloads, and stack-trace context. The dashboard and
connected-client tools that read this data are therefore restricted
to authenticated organization members, and anonymous requests receive
a `404` so route existence is not disclosed. Slack link previews for
error pages return no content.

The ingest endpoint itself remains publicly reachable so any Software
Development Kit ([SDK](https://en.wikipedia.org/wiki/Software_development_kit))
that holds a valid Data Source Name key can send events, but the key
alone grants no other access to the instance.

## Data Source Names

A Data Source Name
([DSN](https://docs.sentry.io/product/sentry-basics/dsn-explainer/))
identifies which project an event belongs to. Every project owns one
or more keys; each key produces a Data Source Name of the form:

```
https://<public_key>@<hive-host>/<numeric_project_id>
```

Software Development Kits that speak the Sentry protocol accept this
value directly. Any of the community-maintained language libraries
work — no Hive-specific integration is required.

The Hive dashboard mints keys for a project from its settings page.
Keys can be labelled to keep long-lived environments apart (for
example, one per deployment) and rotated without downtime.

## Ingest endpoint

Software Development Kits send events as envelopes to
`POST /api/<numeric_project_id>/envelope/` on the deployed host. The endpoint
follows the public Sentry envelope specification:

- Authentication comes from the `X-Sentry-Auth` header. When a client
  cannot set arbitrary headers, the same information may be supplied
  via the `sentry_key` query parameter or embedded in the envelope
  header's `dsn` field.
- Bodies compressed with `gzip` or `deflate` are decoded before
  parsing.
- The endpoint responds with `200 OK` and a JSON body of the form
  `{"id": "<event_id>"}`.
- Non-event items — transactions, sessions, attachments, replays,
  check-ins, profiles, and feedback — are accepted for compatibility
  and silently dropped, so Software Development Kits do not retry
  them.

Events are enqueued for background processing so the response returns
quickly. The worker parses the envelope, groups events by fingerprint
into issues, and appends the raw event to ClickHouse for later
querying.

## Grouping

Events are grouped into issues by a deterministic fingerprint derived
from the exception type, the top in-application stack frame, and a
normalized version of the message. Numeric identifiers in the message
are collapsed so an error affecting many records does not fragment
into a separate issue per record. A Software Development Kit that
supplies an explicit `fingerprint` field overrides this default,
allowing bespoke grouping when required.

## Hive's own errors

The running Hive instance records its own crashes through the same
pipeline. On the first boot with ClickHouse enabled, Hive provisions
a private project named "Hive" and a default Data Source Name key,
and installs an Erlang logger handler that captures error-level and
higher log events. Each captured event is turned into a Sentry-shaped
payload in memory and appended to the same storage that receives
Software Development Kit traffic, so the dashboard and connected-client
tools that surface application errors also surface Hive's own.

No environment variables are required to enable this behaviour. When
ClickHouse is disabled, the handler becomes a no-op.

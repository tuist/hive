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
identifies which project an event belongs to. Every key produces a
Data Source Name of the form:

```
https://<public_key>@<hive-host>/<numeric_project_id>
```

Software Development Kits that speak the Sentry protocol accept this
value directly. Any of the community-maintained language libraries
work — no Hive-specific integration is required.

Hive mints two kinds of Data Source Name:

- **Project-scoped.** Every project has one. Events sent through it are
  attributed to the project only and act as the catch-all for
  subsystems that don't map to a single domain (the server itself,
  one-off scripts, crons). Copy or rotate it from the project's
  settings page.
- **Domain-scoped.** Any project linked to a domain can mint one
  additional key per `(project, domain)` pair. A service that lives
  under one domain — for example, the `registry/` service under a
  "Registry" domain — points its Sentry Software Development Kit at
  the domain-scoped Data Source Name and every event it sends is
  attributed to both the project and the domain at ingest, with no
  per-caller tag. Copy or rotate these from the domain's page; each
  linked project shows its own row, and rotating one only invalidates
  that single credential.

The URL shape is identical for both kinds — the domain does not appear
in it — so any existing Sentry Software Development Kit works without
modification. Deleting or rotating a domain-scoped Data Source Name
cuts off exactly that one subsystem; the project-scoped Data Source
Name and every other domain's Data Source Name keep working.

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

## Resolution

Organization members can resolve, reopen, or ignore an error from the
dashboard or through connected-client tools. Error results returned through
the [Model Context Protocol](https://modelcontextprotocol.io/) include the
error's Hive link. When a connected client fixes an error, it should include
that link in the pull request description. If the repository is linked to the
same Hive project, Hive marks the error as resolved when the pull request is
merged.

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

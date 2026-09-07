# Alerts

Alerts turn signals Hive already collects into notifications on a
destination you choose. v1 covers Hive's own error tracking as the
signal source and Slack as the destination, but the model is generic:
new sources and destinations plug into the same rules.

## Availability

Alerts are available on any Hive instance. Delivering to Slack needs a
[connected Slack workspace](./slack). Alert rules that watch error
issues need [error tracking](./errors) enabled — that is, ClickHouse
running.

## Rules

An alert rule belongs to a single project and combines four things:

- **Trigger** — the condition that fires the rule.
- **Tier** — how urgent the notification is (`attention` vs `incident`).
- **Filters** — optional narrowing (minimum severity level, environment).
- **Destination** — where the message is sent, plus how loudly.

Every rule also has a **cooldown** that prevents the same subject (for
example, one error issue) from firing the same rule twice inside the
configured window.

### Triggers

Two triggers are available today:

- **Issue crosses event rate.** Fires every time an issue accumulates a
  chosen number of new events since the last alert for that same
  (rule, issue) pair. A brand-new issue fires the first time it reaches
  the threshold (baseline is zero), and a long-running incident keeps
  firing as it rolls on. The rule cooldown controls how often those
  re-alerts actually go out.
- **Regression.** Fires when a previously resolved issue is seen again.

More triggers (per-user thresholds, frequency spikes tied to a rolling
event window, etc.) can be added later without breaking existing rules.

### Tiers

The tier tags a rule's urgency:

- **Attention** posts a plain message. Suitable for a low-volume "keep
  an eye on this" channel.
- **Incident** prepends `@here` or `@channel` (per the rule's mention
  setting) so the destination gets a channel-wide ping.

Tiers only change how the destination renders the message; they do not
trigger any workflow inside Hive on their own.

### Filters

Two filters narrow which issues a rule watches:

- **Minimum level.** Ignores events below the chosen severity
  (`warning`, `error`, `fatal`). Leave empty to match every level.
- **Environment.** Case-sensitive equality against the event's
  `environment` field. Leave empty to match every environment.

### Destinations

Two destination types are available.

**Slack.** Post the message into a channel on any Slack workspace
connected through the standard install flow. A rule stores the
workspace, the channel ID, and whether to prefix the message with
`@here`, `@channel`, or nothing. The message is a
[Block Kit](https://docs.slack.dev/block-kit/) payload designed for
one glance: a header carrying the tier and the reason it fired, the
issue title with a link back into Hive, and a fields row that reads
"how bad is this?" — level, environment, event count, first-seen,
last-seen, and current status. `production` renders in bold so an
on-call scanning a busy channel can pick production incidents out of
staging noise. The tier controls the header marker (🚨 for incident,
⚠️ for attention) and the optional mention prefix.

**Webhook.** POST a signed JSON envelope to any HTTPS endpoint —
Grafana, PagerDuty, an in-house receiver. Hive mints a signing secret
when the rule is created; each request carries:

- `Content-Type: application/json` and a JSON body describing the rule,
  the issue, and the project (including a link back into the
  dashboard).
- `X-Hive-Signature: sha256=<hex>` — HMAC-SHA256 of the raw request
  body using the rule's signing secret. Receivers should recompute the
  MAC and reject requests that do not match.
- `Hive-Delivery-Id: <uuid>` — a unique per-attempt identifier
  receivers can use to deduplicate retries.
- `X-Hive-Event: alert.fired`.

### Cooldown

Every rule keeps a per-(rule, subject) log of what it fired. Before a
rule fires again for the same subject, Hive checks the log: if the
previous notification for that subject went out inside the cooldown
window, the new firing is recorded as `skipped` and no message is
sent. Set the cooldown to `0` to disable this check.

## Managing rules

Rules live under **Projects → &lt;project&gt; → Alerts**. Any signed-in
organization member can view a project's rules; only administrators can
create, edit, or delete them, because a misconfigured rule can page a
shared channel.

The audit trail on the alerts page records every send, skip, and
failure for later inspection.

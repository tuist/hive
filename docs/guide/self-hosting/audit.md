## Audit

Hive keeps an append-only audit trail of who did what across every
surface: the dashboard, MCP, webhooks, background jobs, and system
paths. The trail lives in PostgreSQL alongside the rest of the
application data, so nothing extra needs to be wired up to enable it.

## What gets recorded

Each entry captures:

- **Actor**: the user, agent, or system that initiated the action,
  with its id, email, name, and role at the time the entry was
  written.
- **Interface**: where the action came from. One of `dashboard`,
  `mcp`, `webhook`, `worker`, or `system`.
- **Action**: a dotted `domain.verb` string, for example
  `user.signed_in`, `spec.created`, or `spec.updated`.
- **Target**: the resource the action acted on, with its type, id,
  and a human-readable label.
- **Metadata**: a JSON blob with any extra context the action chose
  to record.
- **Time**: when the action occurred, in UTC.

User sign-ins, sign-outs, and spec creation and updates are
recorded out of the box. Agent-run workflows attribute their
entries to the agent module name, with the model id captured in
metadata, so when an agent drives one of those actions you can
trace which model produced the side effect.

## Who sees it

Access to the audit trail is gated by the `admin` role on the user
record. See [Authorization](./authorization) for the three roles,
how they are derived from `HIVE_ORG_DOMAINS`, and how to promote a
user to `admin`.

## MCP tools

Two MCP tools expose the same data the dashboard does, gated by the
same admin check:

- `list_audit_activities`: paginated listing with filters for
  interface, action, actor kind, and target type.
- `get_audit_activity`: fetch a single entry by id.

Non-admin callers receive `{"error": "forbidden"}`. The tools are
always registered, so admins can use the trail from any MCP-aware
client without extra configuration.

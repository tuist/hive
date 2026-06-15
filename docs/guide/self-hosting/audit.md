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
  `user.signed_in`, `spec.created`, or `meadow.webhook_received`.
- **Target**: the resource the action acted on, with its type, id,
  and a human-readable label.
- **Metadata**: a JSON blob with any extra context the action chose
  to record.
- **Time**: when the action occurred, in UTC.

User sign-ins, spec creation and updates, meadow webhooks, forage
ingestion events, and similar workflows are recorded out of the box.
Agentic workflows record entries with the agent module name as the
actor and the model id in metadata, so you can trace which model
produced which side effect.

## Who sees it

Access to the audit trail is gated by a persisted role on the user
record. There are two roles:

- `member` (default): every signed-in user starts here. Members can
  use Hive normally but cannot reach the audit trail.
- `admin`: members promoted to admin can see the trail at `/audit`
  and call the audit MCP tools.

The admin role is distinct from email-domain-based org membership
(`HIVE_GOOGLE_ALLOWED_DOMAINS` and the equivalent generic-OIDC
allowlist). Domain allowlisting gates who can sign in. The admin
role gates who sees the trail among those signed in.

## Promoting an admin

There is no UI for changing a user's role yet. Attach a remote IEx
to a running instance and promote by email. For a Helm-deployed
Hive, that looks like:

```bash
kubectl exec -it deploy/hive -- bin/hive remote
```

Then in the IEx prompt:

```elixir
user = Hive.Accounts.get_user_by_email("admin@example.com")
{:ok, _user} = Hive.Accounts.update_user_role(user, :admin)
```

Demote the same way, passing `:member` instead. The change takes
effect on the user's next request.

## MCP tools

Two MCP tools expose the same data the dashboard does, gated by the
same admin check:

- `list_audit_activities`: paginated listing with filters for
  interface, action, actor kind, and target type.
- `get_audit_activity`: fetch a single entry by id.

Non-admin callers receive `{"error": "forbidden"}`. The tools are
always registered, so admins can use the trail from any MCP-aware
client without extra configuration.

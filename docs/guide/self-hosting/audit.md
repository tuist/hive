# Audit

Hive keeps an append-only record of important activity from people,
agents, webhooks, scheduled work, and system operations.

Administrators can open **Ops (Operations) → Audit** at `/ops/audit`.

## Find an activity

The audit table shows:

- **Time**: when the activity happened.
- **Actor**: the person, agent, or system responsible.
- **Source**: whether the activity came from the dashboard, a connected
  client, a webhook, scheduled work, or Hive itself.
- **Action**: what happened, such as signing in or creating a spec.
- **Target**: the project, spec, account, or other resource affected.

Use the search field to search actors, actions, targets, and additional
context. Filters can narrow the list by source, action, actor type, or
target type. When a target still exists, select it to open the related
dashboard page.

## What Hive records

Hive records account sign-ins and sign-outs, changes to specs and other
managed resources, integration activity, and actions performed by
language-model workflows. Entries retain the actor and role that applied
when the activity occurred.

The audit trail is intended for operational investigation and change
history. It does not replace application error reporting or infrastructure
logs.

## Connected-client access

The same administrator-only data is available to
[Model Context Protocol](https://modelcontextprotocol.io/) clients through
`list_audit_activities` and `get_audit_activity`. These tools use the same
authorization rules as the dashboard.

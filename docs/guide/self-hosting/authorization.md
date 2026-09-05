# Authorization

Every Hive account has one role. The role controls access consistently
across the dashboard and connected clients.

## Roles

- **Collaborator** is signed in but is outside the organization.
  Collaborators can view public content, submit Forage items, comment on
  visible work, and edit items they authored.
- **Member** belongs to the organization. Members can also see private
  content, create projects, domains, and specs, and manage the team's
  product work.
- **Administrator** has every member capability and can manage
  Operations settings, connected workspaces, model providers, and the
  audit trail.

At first sign-in, Hive compares the account's email domain with
[`HIVE_ORG_DOMAINS`](/reference/configuration#hive_org_domains). A match
creates a member; a non-match creates a collaborator. When no
organization domains are configured, every signed-in account becomes a
member.

Changing the configured domains later does not change existing roles.

## What each role can do

| Capability | Anonymous | Collaborator | Member | Administrator |
|---|---|---|---|---|
| View public projects, domains, specs, postmortems, and drops | yes | yes | yes | yes |
| Use the mobile application to view visible Forage items, specs, and Drops | no | yes | yes | yes |
| Submit Forage items | no | yes | yes | yes |
| Comment on visible Forage items and specs | no | yes | yes | yes |
| Create Forage items as GitHub issues | no | no | yes | yes |
| Start and inspect Flights | no | no | yes | yes |
| View private product work | no | no | yes | yes |
| Create and manage projects, domains, specs, and postmortems | no | no | yes | yes |
| Manage Forage intake | no | no | no | yes |
| Manage error summary scheduling and delivery | no | no | no | yes |
| Manage Slack and model gateway settings | no | no | no | yes |
| View the audit trail | no | no | no | yes |
| View captured errors and update their status | no | no | yes | yes |
| See a project's Sentry-compatible Data Source Name | no | no | yes | yes |
| Rotate a project's Sentry-compatible Data Source Name | no | no | no | yes |
| See a domain-scoped Sentry-compatible Data Source Name | no | no | yes | yes |
| Rotate a domain-scoped Sentry-compatible Data Source Name | no | no | no | yes |
| View a project's alert rules | no | no | yes | yes |
| Create, edit, or delete alert rules | no | no | no | yes |

Anonymous access also depends on
[`HIVE_VISIBILITY`](/reference/configuration#hive_visibility). A private
instance requires sign-in before any dashboard content is shown.

## Resource visibility

Projects, domains, and postmortems can be public or private. Specs inherit
their project's visibility and can be narrowed to private, but a spec in a
private project cannot be made public. Public postmortems can only be associated
with public domains.

Public feeds and Slack link previews follow the anonymous view. Content
that requires a Hive session is not included.

## Change an account role

Role management is not yet available in the dashboard. Until it is,
role changes require an operator-side maintenance action. Ask the person
who runs your Hive instance to promote or demote the account.

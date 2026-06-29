# Authorization

Hive uses a single persisted role on each user record to decide what
that user can see and do. There are three roles, ordered weakest to
strongest:

- `collaborator`: signed in, but not part of the org. The default for
  anyone whose email domain is not in
  [`HIVE_ORG_DOMAINS`](/reference/configuration#hive_org_domains). Collaborators
  can sign in, comment on forage items they submitted, and see public
  domains and projects.
- `member`: part of the org. The default for users whose email domain
  matches [`HIVE_ORG_DOMAINS`](/reference/configuration#hive_org_domains) at
  signup, and for every signed-in user when no org domains are
  configured. Members can see private domains and projects, create
  specs, and act on the dashboard or
  [Model Context Protocol](https://modelcontextprotocol.io/) endpoint
  the way the team does.
- `admin`: explicitly promoted. Admins additionally see the audit
  trail at `/ops/audit` and reach the Operations surfaces at `/ops/*`,
  where they manage Slack workspaces and drop sources.

The role is derived from the email domain the first time a user signs
in and then stored. Changing
[`HIVE_ORG_DOMAINS`](/reference/configuration#hive_org_domains) later does not
reclassify existing users; promote and demote with
`Hive.Accounts.update_user_role/2`.

## What each role can do

| Surface | Anonymous | `collaborator` | `member` | `admin` |
|---|---|---|---|---|
| Public domains, projects, specs, drops | yes | yes | yes | yes |
| Sign-in, create forage items | no | yes | yes | yes |
| Private domains, projects, specs, drops | no | no | yes | yes |
| Spec editing | no | own only | yes | yes |
| Audit trail (`/ops/audit`) | no | no | no | yes |
| Operations surfaces (`/ops/*`): Slack and drop sources | no | no | no | yes |

Anonymous access also depends on
[`HIVE_VISIBILITY`](/reference/configuration#hive_visibility). When the instance
is `private` everyone must sign in first, including for the public content
listed above.

## Promoting an admin

::: tip Planned dashboard control
Hive does not yet expose role management in the dashboard. A dashboard
control is planned so administrators can promote and demote users
without opening a remote shell.
:::

Until then, open a remote Interactive Elixir
([IEx](https://hexdocs.pm/iex/IEx.html)) shell in the running Hive
release and promote the user by email. The command depends on how the
instance is deployed, but the important part is running
`bin/hive remote` against the live application.

For a Helm release named `hive` on Kubernetes:

```bash
kubectl exec -it deploy/hive -- bin/hive remote
```

For a Docker Compose service named `hive`:

```bash
docker compose exec hive bin/hive remote
```

For any other process manager, open a shell in the host or container
running the Hive release and run:

```bash
bin/hive remote
```

Then in the Interactive Elixir shell:

```elixir
user = Hive.Accounts.get_user_by_email("admin@example.com")
{:ok, _user} = Hive.Accounts.update_user_role(user, :admin)
```

Demote the same way, passing `:member` or `:collaborator` instead. The
change takes effect on the user's next request.

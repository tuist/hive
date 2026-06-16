## Self-hosting

Hive is shipped as a single Phoenix application backed by PostgreSQL.
The container image lives at `ghcr.io/tuist/hive` and the Helm chart at
`oci://ghcr.io/tuist/charts/hive`. Both artifacts are released from the
[tuist/hive](https://github.com/tuist/hive) repository on every push to
`main`.

## Visibility

`HIVE_VISIBILITY` controls who can reach the dashboard:

- `public` (default): anyone can use the instance without logging in.
- `private`: routes are gated behind login; only authenticated users
  (passing any configured provider's domain allowlist) can access them.

The login page is always available so administrators can sign in even
on public instances.

## What you need

- A Kubernetes cluster (or any environment that can run the container
  image) with PostgreSQL reachable from the app.
- A `SECRET_KEY_BASE` generated with `mix phx.gen.secret` (or any
  64-byte random value).
- At least one OIDC provider configured if you plan to run with
  `HIVE_VISIBILITY=private`. See [Authentication](./authentication).

## Next

- [Authentication](./authentication) explains how to wire up Google and
  generic OIDC providers.
- [Slack](./slack) covers connecting Slack workspaces so Hive can reply
  in threads and capture messages as feature requests.
- [Deployment](./deployment) walks through installing the Helm chart and
  the minimum values you need to provide.

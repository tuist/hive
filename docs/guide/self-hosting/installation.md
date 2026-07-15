# Install Hive

Hive is distributed as a container image. Run one instance for each
organization and connect it to a PostgreSQL database.

Your deployment platform must provide:

- A stable public address with a secure connection.
- A PostgreSQL database that persists across releases.
- A secret manager for Hive credentials.
- A way to run database migrations before a new release starts serving
  requests.

## Configure the required settings

Every production installation needs these settings:

```text
DATABASE_URL=ecto://USER:PASSWORD@HOST/DATABASE
SECRET_KEY_BASE=<a cryptographically secure 64-byte value>
PHX_HOST=hive.example.com
```

`DATABASE_URL` connects Hive to PostgreSQL. `SECRET_KEY_BASE` protects
session data and must remain secret and stable across releases.
`PHX_HOST` is the public host name Hive uses when creating links.

The container listens on port `4000` unless [`PORT`](/reference/configuration#port)
is set. See the [configuration reference](/reference/configuration) for
all optional settings.

## Start with a public instance

Hive is public by default. This lets you confirm that the installation is
healthy before depending on an external sign-in provider.

Deploy the published
[`ghcr.io/tuist/hive`](https://github.com/orgs/tuist/packages/container/package/hive)
image through your normal container platform. Run the image's migration
command before starting the web process whenever the release changes.

## Verify the installation

Open `https://hive.example.com/ready`. A successful response confirms
that Hive can reach its database and accept requests. Then open
`https://hive.example.com` to see the dashboard.

If the readiness check fails, review the migration and application logs
through your deployment platform. Confirm that the database address,
public host name, and session secret are available to both processes.

## Continue setup

1. Configure [authentication](./authentication) before making the
   instance private.
2. Review the [role and visibility model](./authorization).
3. Create the first [project](/guide/using-hive/projects).
4. Connect the [GitHub integration](./github) if projects should ingest
   issues and releases.
5. Review [Deployment options](./deployment) for backups, object storage,
   secret management, and error reporting.

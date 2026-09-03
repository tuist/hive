# Deployment options

Start with [Install Hive](./installation) for the required hosting
contract. This page covers the choices that commonly differ between
production environments.

## Application processes

A Hive release has two responsibilities:

- Run database migrations before the new application version starts.
- Run the web process and expose its configured port through the public
  Hive address.

Keep these responsibilities in the same release so the application and
database schema move forward together. Run a single web instance unless
your platform has been tested with a different topology.

## Visibility and authentication

Instances are public by default. Configure and test at least one
[authentication provider](./authentication) before setting
`HIVE_VISIBILITY=private`.

## Search engines

Public instances publish a sitemap at `/sitemap.xml` and advertise it from
`/robots.txt`. The sitemap contains only public collections and public items,
so search engines can discover content without being directed to account,
operational, or editing pages.

Private instances block crawlers in `/robots.txt`, do not publish a sitemap,
and require a signed-in session before serving dashboard pages.

Store provider credentials in the deployment's secret manager. Make
them available to both migrations and the web process when the platform
uses separate execution environments.

## Database storage and backups

Hive requires PostgreSQL with durable storage. Size the database for the
number of product signals, specs, comments, audit activities, and model
usage records the organization expects to retain.

Use the database provider's normal backup system. Test both backup
creation and restore before relying on it for production recovery. A
backup is only useful once a restore has been proven against a clean
environment.

## Object storage

Hive can use
[Amazon Simple Storage Service](https://aws.amazon.com/s3/)-compatible
storage for features that need durable objects. It is disabled by
default.

Set `HIVE_OBJECT_STORAGE_PROVIDER=s3` and provide the bucket, region,
endpoint, access key, and secret key listed under
[Object storage](/reference/configuration#object-storage). Keep storage
credentials in the deployment's secret manager.

## Secret management

Keep the session secret, database address, provider credentials, and
integration signing secrets outside source control and deployment
manifests.

Use the secret manager already supported by your hosting platform. Make
secret rotation a deliberate operation: update the stored value,
redeploy Hive, verify the affected integration, and revoke the previous
credential when the provider supports revocation.

Do not rotate `SECRET_KEY_BASE` during a routine release. Changing it
invalidates existing sessions.

## ClickHouse

The Helm chart can run a single-node [ClickHouse](https://clickhouse.com/)
database with a persistent volume:

```yaml
clickhouse:
  enabled: true
  persistence:
    size: 50Gi
    storageClass: your-block-storage-class
```

The ClickHouse volume survives pod replacement. Back up or snapshot the
volume according to the storage provider's recovery model.

The embedded deployment is intentionally a single stateful server. Use the
`nodeSelector` and `tolerations` chart values to place it on a dedicated
cluster worker when needed. It does not provide high availability, so use a
managed ClickHouse service for installations that require it. Leaving
ClickHouse disabled does not affect features that only use PostgreSQL.

## Error reporting

Hive tracks errors natively when ClickHouse is enabled. Application
crashes from the running Hive instance are recorded against a
private, auto-provisioned "Hive" project, and every dashboard, feed,
and Model Context Protocol tool that surfaces application errors also
surfaces Hive's own. Any Sentry-compatible Software Development Kit
can point at
`POST /api/&lt;project_id&gt;/envelope/` on the deployed host and its
project key to record its own errors alongside them.

Leaving ClickHouse disabled disables error tracking; nothing else is
affected.

## Production checklist

Before opening the instance to users:

1. Confirm `/ready` succeeds through the public address.
2. Test database backup and restore.
3. Sign in with every configured authentication provider.
4. Confirm an account outside the allowed domains is rejected.
5. Verify that public and private content behave as described in
   [Authorization](./authorization).
6. Connect a test repository and confirm that issues and releases appear.
7. Review secret rotation and incident-recovery procedures with the
   operators responsible for the deployment platform.

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

## Choose a deployment method

### Run the container directly

Create an environment file containing the required settings and any optional
provider credentials. Generate the session secret once and keep it stable:

```bash
mix phx.gen.secret
```

Set the generated value as `SECRET_KEY_BASE`, then run the release migration
before starting the web process. Replace `<version>` with the Hive release you
want to run:

```bash
export HIVE_IMAGE=ghcr.io/tuist/hive:<version>

docker run --rm --env-file .env "$HIVE_IMAGE" \
  /app/bin/hive eval "Hive.Release.migrate"

docker run --detach --name hive --env-file .env --publish 4000:4000 "$HIVE_IMAGE"
```

The migration container must be able to reach the same PostgreSQL database as
the web container. If the two containers use a Docker network, attach both
commands to that network with `--network`. Run the migration again for each
release before replacing the web container.

### Deploy with Helm

The published chart is available from the Hive OCI registry. Its default
configuration creates a PostgreSQL cluster through CloudNativePG and an
Ingress through ingress-nginx and cert-manager, so install those operators and
make a storage class available first. The chart can also use an existing
PostgreSQL service and existing secret-manager integration through its values.

Create the application secret with at least a stable session secret:

```bash
kubectl create namespace hive
kubectl -n hive create secret generic hive-app \
  --from-literal=SECRET_KEY_BASE="$(mix phx.gen.secret)"
```

Install a chart release and set the public hostname. Use the chart version that
matches the application release you select:

```bash
helm upgrade --install hive oci://ghcr.io/tuist/charts/hive \
  --version <chart-version> \
  --namespace hive \
  --set host=hive.example.com \
  --set secrets.existingSecret=hive-app
```

Review the chart's [`values.yaml`](https://github.com/tuist/hive/blob/main/infra/helm/hive/values.yaml)
for storage, backups, authentication, object storage, ClickHouse, and external
secret-manager settings. Keep credentials in Kubernetes Secrets or the
external secret manager rather than in a values file.

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

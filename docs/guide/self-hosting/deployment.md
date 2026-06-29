# Deployment

The Helm chart published at
[`oci://ghcr.io/tuist/charts/hive`](https://github.com/tuist/hive/pkgs/container/charts%2Fhive)
is generic, so any team can deploy their own Hive instance with it.
The defaults assume no External Secrets Operator, no image pull secret,
and no S3 backup; you bring your own Kubernetes Secret for
[`SECRET_KEY_BASE`](/reference/configuration#secret_key_base) (and any OAuth
credentials) and point at it via `secrets.existingSecret`, then run
`helm upgrade --install`.

## What you need

- A Kubernetes cluster (or any environment that can run the container
  image) with PostgreSQL reachable from the app.
- A [`SECRET_KEY_BASE`](/reference/configuration#secret_key_base) generated with
  `mix phx.gen.secret` (or any 64-byte random value).
- At least one OIDC provider configured if you plan to run with
  [`HIVE_VISIBILITY`](/reference/configuration#hive_visibility) set to `private`.
  See [Authentication](./authentication).

## Visibility

[`HIVE_VISIBILITY`](/reference/configuration#hive_visibility) controls who can
reach the dashboard:

- `public` (default): anyone can use the instance without logging in.
- `private`: routes are gated behind login; only authenticated users
  (passing any configured provider's domain allowlist) can access them.

The login page is always available so administrators can sign in even
on public instances.

## Minimum bring-your-own setup

```bash
kubectl create namespace hive
kubectl -n hive create secret generic hive-app \
  --from-literal=SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  --from-literal=HIVE_GOOGLE_CLIENT_ID="..." \
  --from-literal=HIVE_GOOGLE_CLIENT_SECRET="..." \
  --from-literal=HIVE_S3_ACCESS_KEY_ID="..." \
  --from-literal=HIVE_S3_SECRET_ACCESS_KEY="..."

helm upgrade --install hive oci://ghcr.io/tuist/charts/hive \
  --namespace hive \
  --set host=hive.example.com \
  --set env.HIVE_VISIBILITY=private \
  --set env.HIVE_GOOGLE_ALLOWED_DOMAINS=example.com \
  --set env.HIVE_OBJECT_STORAGE_PROVIDER=s3 \
  --set env.HIVE_S3_BUCKET=hive-objects \
  --set env.HIVE_S3_REGION=us-east-1 \
  --set env.HIVE_S3_ENDPOINT_URL=https://s3.example.com
```

## Object storage

Hive can be configured with S3-compatible object storage for features
that need durable blobs. Set
[`HIVE_OBJECT_STORAGE_PROVIDER`](/reference/configuration#hive_object_storage_provider)
to `s3` and provide:

- [`HIVE_S3_BUCKET`](/reference/configuration#hive_s3_bucket)
- [`HIVE_S3_REGION`](/reference/configuration#hive_s3_region)
- [`HIVE_S3_ENDPOINT_URL`](/reference/configuration#hive_s3_endpoint_url)
  (required for S3-compatible providers such as Hetzner)
- [`HIVE_S3_ACCESS_KEY_ID`](/reference/configuration#hive_s3_access_key_id)
- [`HIVE_S3_SECRET_ACCESS_KEY`](/reference/configuration#hive_s3_secret_access_key)
- [`HIVE_S3_PUBLIC_BASE_URL`](/reference/configuration#hive_s3_public_base_url)
  (optional, used when public links should use a content delivery
  network or custom domain)
- [`HIVE_S3_FORCE_PATH_STYLE`](/reference/configuration#hive_s3_force_path_style)
  (optional, `true` or `1`; useful for S3-compatible providers)

## Error reporting

Hive can send application errors to Sentry when you provide
[`SENTRY_DSN`](/reference/configuration#sentry_dsn). The value is the Sentry
[Data Source Name](https://docs.sentry.io/product/sentry-basics/dsn-explainer/)
for the project that should receive events. When
[`SENTRY_DSN`](/reference/configuration#sentry_dsn) is unset, Hive does not send
events and the rest of the application behaves the same as a deployment
without Sentry.

When Sentry is enabled, Hive reports Phoenix request errors, LiveView
errors with request context, and Oban job failures. Oban failures are
reported only after a job exhausts all attempts by default, so retryable
failures do not create noise while Oban is still recovering. Scheduled
Oban jobs also send Sentry check-ins by default so Sentry can monitor
whether they are running on time.

Optional variables:

- [`SENTRY_ENVIRONMENT`](/reference/configuration#sentry_environment): tags
  events with the deployment environment. The Helm chart defaults this
  to `production`.
- [`SENTRY_RELEASE`](/reference/configuration#sentry_release): tags events with
  the deployed release. Tuist's
  deployment workflow sets this to the deployed commit identifier; other
  deployments can set it to an image tag, release version, or commit.
- [`SENTRY_OBAN_CAPTURE_ERRORS`](/reference/configuration#sentry_oban_capture_errors):
  captures failed Oban job attempts. Defaults to `true` in the Helm
  chart.
- [`SENTRY_OBAN_REPORT_RETRIES`](/reference/configuration#sentry_oban_report_retries):
  reports retryable Oban failures before the final attempt. Defaults to
  `false`; set it to `true` to report every failed attempt.
- [`SENTRY_OBAN_CRON_MONITORING`](/reference/configuration#sentry_oban_cron_monitoring):
  sends Sentry check-ins for scheduled Oban jobs. Defaults to `true` in
  the Helm chart.

For a manually managed Kubernetes Secret, add the Sentry value beside
the rest of the app secrets:

```bash
kubectl -n hive create secret generic hive-app \
  --from-literal=SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  --from-literal=SENTRY_DSN="https://examplePublicKey@o0.ingest.sentry.io/0"
```

When using the Helm chart with External Secrets, map
[`SENTRY_DSN`](/reference/configuration#sentry_dsn) to the secret reference in
your values overlay:

```yaml
env:
  SENTRY_OBAN_CAPTURE_ERRORS: "true"
  SENTRY_OBAN_REPORT_RETRIES: "false"
  SENTRY_OBAN_CRON_MONITORING: "true"

externalSecrets:
  enabled: true
  items:
    SENTRY_DSN:
      remoteRef: "hive-sentry/dsn"
```

## Vector database

Hive can also point at an `opendata-vector` HTTP database for embedding
search. Set
[`HIVE_OPENDATA_VECTOR_URL`](/reference/configuration#hive_opendata_vector_url)
to the vector service base address, for example
`http://hive-vector:8080`.

The Helm chart includes an optional `opendata-vector` deployment under
`vector.*`. It is disabled by default so self-hosted installs only need
Postgres to boot. When enabled, vectors are stored in an S3-compatible
bucket and the pod uses a PVC as a local cache. It reuses Hive's
object storage credentials from the app Secret and stores the index
under `vector.storage.prefix`.

To enable the bundled vector database on the same object storage
bucket, enable `vector.*` and choose a prefix:

```bash
helm upgrade --install hive oci://ghcr.io/tuist/charts/hive \
  --namespace hive \
  --reuse-values \
  --set vector.enabled=true \
  --set vector.storage.prefix=vector
```

## External Secrets

If you run External Secrets Operator, enable `externalSecrets.enabled`
and provide `storeRef` + `items` pointing at your backend (Vault, AWS
Secrets Manager, 1Password, etc.) in your own values overlay.

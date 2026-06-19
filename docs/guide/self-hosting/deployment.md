## Deployment

The Helm chart published at
[`oci://ghcr.io/tuist/charts/hive`](https://github.com/tuist/hive/pkgs/container/charts%2Fhive)
is generic, so any team can deploy their own Hive instance with it.
The defaults assume no External Secrets Operator, no image pull secret,
and no S3 backup; you bring your own Kubernetes Secret for
`SECRET_KEY_BASE` (and any OAuth credentials) and point at it via
`secrets.existingSecret`, then run `helm upgrade --install`.

## What you need

- A Kubernetes cluster (or any environment that can run the container
  image) with PostgreSQL reachable from the app.
- A `SECRET_KEY_BASE` generated with `mix phx.gen.secret` (or any
  64-byte random value).
- At least one OIDC provider configured if you plan to run with
  `HIVE_VISIBILITY=private`. See [Authentication](./authentication).

## Visibility

`HIVE_VISIBILITY` controls who can reach the dashboard:

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
that need durable blobs. Set `HIVE_OBJECT_STORAGE_PROVIDER=s3` and
provide:

- `HIVE_S3_BUCKET`
- `HIVE_S3_REGION`
- `HIVE_S3_ENDPOINT_URL` (required for S3-compatible providers such as
  Hetzner)
- `HIVE_S3_ACCESS_KEY_ID`
- `HIVE_S3_SECRET_ACCESS_KEY`
- `HIVE_S3_PUBLIC_BASE_URL` (optional, used when public URLs should use
  a CDN or custom domain)
- `HIVE_S3_FORCE_PATH_STYLE` (optional, `true` or `1`; useful for
  S3-compatible providers)

## Vector database

Hive can also point at an `opendata-vector` HTTP database for embedding
search. Set `HIVE_OPENDATA_VECTOR_URL` to the vector service base URL,
for example `http://hive-vector:8080`.

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

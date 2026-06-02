<p align="center">
  <img src="priv/static/images/logo.png" alt="Hive" width="20%" />
</p>

<h1 align="center">Hive</h1>

<p align="center">
  <a href="https://github.com/tuist/hive/actions/workflows/hive.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/tuist/hive/hive.yml?branch=main&label=ci&style=flat-square" alt="CI" />
  </a>
  <a href="https://github.com/tuist/hive/actions/workflows/deploy.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/tuist/hive/deploy.yml?branch=main&label=deploy&style=flat-square" alt="Deployment" />
  </a>
  <a href="https://github.com/tuist/hive/releases">
    <img src="https://img.shields.io/github/v/release/tuist/hive?label=release&style=flat-square" alt="Latest release" />
  </a>
  <a href="https://github.com/tuist/hive/pkgs/container/hive">
    <img src="https://img.shields.io/badge/image-ghcr.io%2Ftuist%2Fhive-2496ED?style=flat-square" alt="GHCR image" />
  </a>
  <a href="LICENSE.md">
    <img src="https://img.shields.io/github/license/tuist/hive?style=flat-square" alt="MPL-2.0 license" />
  </a>
  <a href="https://elixir-lang.org">
    <img src="https://img.shields.io/badge/language-Elixir-4B275F?style=flat-square" alt="Elixir" />
  </a>
</p>

At Tuist we've reimagined how we shape and build product by leaning into
LLMs and agentic workflows, and Hive is our take on it. It's built to run
inside our own team and equally to be opened up to the people who use
your products.

Hive is licensed under [MPL-2.0](LICENSE.md). We don't offer it as a
managed service, but you can try our own instance at
<https://hive.tuist.dev>, or self-host your own.

## Self-hosting

### Visibility

`HIVE_VISIBILITY` controls who can reach the dashboard:

- `public` (default): anyone can use the instance without logging in.
- `private`: routes are gated behind login; only authenticated users
  (passing any configured provider's domain allowlist) can access them.

### Authentication

Hive's login is available regardless of visibility (so admins can sign
in to a public instance). Auth is delegated to [Ueberauth] +
[ueberauth_oidcc]; any number of providers can be enabled simultaneously
and will appear as buttons on the login screen.

[Ueberauth]: https://github.com/ueberauth/ueberauth
[ueberauth_oidcc]: https://github.com/erlef/ueberauth_oidcc

#### Google

- `HIVE_GOOGLE_CLIENT_ID`
- `HIVE_GOOGLE_CLIENT_SECRET`
- `HIVE_GOOGLE_ALLOWED_DOMAINS` (optional, comma-separated list of email
  domains to accept; e.g. `tuist.dev`). When a single domain is set,
  the authorize redirect also includes Google's `hd=` hint to pre-filter
  the account picker. The check is enforced on the callback regardless.

Callback URL: `/auth/google/callback` on the deployed host.

#### Generic OpenID Connect

Any OIDC provider with a `.well-known/openid-configuration` endpoint:

- `HIVE_OIDC_ISSUER`: the issuer base URL. Hive's auth client discovers
  authorize/token/userinfo endpoints from `<issuer>/.well-known/openid-configuration`.
- `HIVE_OIDC_CLIENT_ID`
- `HIVE_OIDC_CLIENT_SECRET` (optional)
- `HIVE_OIDC_DISPLAY_NAME` (optional, label on the login button; defaults to "Identity provider")
- `HIVE_OIDC_ALLOWED_DOMAINS` (optional, comma-separated allowlist)

Callback URL: `/auth/oidc/callback` on the deployed host.

### Object storage

Hive can be configured with S3-compatible object storage for features
that need durable blobs. Set `HIVE_OBJECT_STORAGE_PROVIDER=s3` and
provide:

- `HIVE_S3_BUCKET`
- `HIVE_S3_REGION`
- `HIVE_S3_ENDPOINT_URL` (required for S3-compatible providers such as Hetzner)
- `HIVE_S3_ACCESS_KEY_ID`
- `HIVE_S3_SECRET_ACCESS_KEY`
- `HIVE_S3_PUBLIC_BASE_URL` (optional, used when public URLs should use a CDN or custom domain)
- `HIVE_S3_FORCE_PATH_STYLE` (optional, `true` or `1`; useful for S3-compatible providers)

### Vector database

Hive can also point at an `opendata-vector` HTTP database for embedding search. Set
`HIVE_OPENDATA_VECTOR_URL` to the vector service base URL, for example
`http://hive-vector:8080`.

The Helm chart includes an optional `opendata-vector` deployment under
`vector.*`. It is disabled by default so self-hosted installs only need
Postgres to boot. When enabled, vectors are stored in an S3-compatible
bucket and the pod uses a PVC as a local cache. It reuses Hive's object
storage credentials from the app Secret and stores the index under
`vector.storage.prefix`.

#### Setting up Google OAuth

1. Open <https://console.cloud.google.com/apis/credentials> in the Google
   Cloud project you want to use.
2. Configure the OAuth consent screen (User type **Internal** for a
   workspace, **External** otherwise; scopes `openid`, `profile`, `email`).
3. **Create Credentials → OAuth client ID → Web application**.
4. Add the **Authorized redirect URI** for each environment, e.g.
   `https://hive.example.com/auth/google/callback`.
5. Copy the Client ID and Client Secret into `HIVE_GOOGLE_CLIENT_ID` and
   `HIVE_GOOGLE_CLIENT_SECRET`.

### Deployment

The Helm chart in `infra/helm/hive` is generic, so anyone can deploy
their own Hive instance with it. The defaults assume no External Secrets
Operator, no image pull secret, and no S3 backup; you bring your own
Kubernetes Secret for `SECRET_KEY_BASE` (and any OAuth credentials) and
point at it via `secrets.existingSecret`, then `helm upgrade --install`.

Minimum bring-your-own setup:

```bash
kubectl create namespace hive
kubectl -n hive create secret generic hive-app \
  --from-literal=SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  --from-literal=HIVE_GOOGLE_CLIENT_ID="..." \
  --from-literal=HIVE_GOOGLE_CLIENT_SECRET="..." \
  --from-literal=HIVE_S3_ACCESS_KEY_ID="..." \
  --from-literal=HIVE_S3_SECRET_ACCESS_KEY="..."

helm upgrade --install hive infra/helm/hive \
  --namespace hive \
  --set host=hive.example.com \
  --set env.HIVE_VISIBILITY=private \
  --set env.HIVE_GOOGLE_ALLOWED_DOMAINS=example.com \
  --set env.HIVE_OBJECT_STORAGE_PROVIDER=s3 \
  --set env.HIVE_S3_BUCKET=hive-objects \
  --set env.HIVE_S3_REGION=us-east-1 \
  --set env.HIVE_S3_ENDPOINT_URL=https://s3.example.com
```

To enable the bundled vector database on the same object storage bucket,
enable `vector.*` and choose a prefix:

```bash
helm upgrade --install hive infra/helm/hive \
  --namespace hive \
  --reuse-values \
  --set vector.enabled=true \
  --set vector.storage.prefix=vector
```

If you run External Secrets Operator, enable `externalSecrets.enabled`
and provide `storeRef` + `items` pointing at your backend (Vault,
AWS Secrets Manager, 1Password, etc.) in your own values overlay.

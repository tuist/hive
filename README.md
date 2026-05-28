<img src="priv/static/images/logo.png" alt="Hive" width="30%" />

# Hive

At Tuist we've reimagined how we shape and build product by leaning into
LLMs and agentic workflows, and Hive is our take on it — built to run
inside our own team and equally to be opened up to the people who use
your products.

## Authentication

Hive runs without authentication by default. Set `HIVE_AUTH_MODE=oidc` to gate
all routes behind login. Any combination of the providers below can be
enabled simultaneously and will appear as buttons on the login screen.

### Google

- `HIVE_GOOGLE_CLIENT_ID`
- `HIVE_GOOGLE_CLIENT_SECRET`
- `HIVE_GOOGLE_SCOPES` (optional, defaults to `openid profile email`)
- `HIVE_GOOGLE_ALLOWED_DOMAINS` (optional, comma-separated list of email
  domains to accept; e.g. `tuist.dev`). When a single domain is set,
  the authorize URL also includes Google's `hd=` hint so the account
  picker is pre-filtered. The check is enforced on the callback — a
  user from any other domain is rejected even if `hd=` is bypassed.

Callback URL: `/auth/google/callback` on the deployed host.

Create the OAuth client in Google Cloud Console:

1. Open <https://console.cloud.google.com/apis/credentials> in the Google
   Cloud project you want to use.
2. Configure the OAuth consent screen if you haven't already (User type
   "Internal" for a workspace, "External" otherwise; scopes `openid`,
   `profile`, `email`).
3. Click **Create Credentials → OAuth client ID**, type **Web application**.
4. Add the **Authorized redirect URI** for each environment:
   - Production: `https://hive.tuist.dev/auth/google/callback`
   - Local dev (if needed): `http://localhost:<port>/auth/google/callback`
5. After creating, copy the **Client ID** and **Client secret** — these become
   `HIVE_GOOGLE_CLIENT_ID` and `HIVE_GOOGLE_CLIENT_SECRET`.

### Generic OpenID Connect

- `HIVE_OIDC_CLIENT_ID`
- `HIVE_OIDC_AUTHORIZE_URL`
- `HIVE_OIDC_TOKEN_URL`
- `HIVE_OIDC_CLIENT_SECRET` (optional)
- `HIVE_OIDC_USERINFO_URL` (optional)
- `HIVE_OIDC_SCOPES` (optional, defaults to `openid profile email`)
- `HIVE_AUTH_PROVIDER_NAME` (optional, label on the login button)
- `HIVE_OIDC_ALLOWED_DOMAINS` (optional, comma-separated list of email
  domains to accept)

Callback URL: `/auth/oidc/callback` on the deployed host.

### Branding

- `HIVE_PRODUCT_NAME` and `HIVE_PRODUCT_TAGLINE` control the login copy.

## Deploying Hive

The Helm chart in `infra/helm/hive` is generic — anyone can deploy their
own Hive instance with it. The defaults assume no External Secrets
Operator, no image pull secret, and no S3 backup; you bring your own
Kubernetes Secret for `SECRET_KEY_BASE` (and any OAuth credentials) and
point at it via `secrets.existingSecret`, then `helm upgrade --install`.

Minimum bring-your-own setup:

```bash
kubectl create namespace hive
kubectl -n hive create secret generic hive-app \
  --from-literal=SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  --from-literal=HIVE_GOOGLE_CLIENT_ID="..." \
  --from-literal=HIVE_GOOGLE_CLIENT_SECRET="..."

helm upgrade --install hive infra/helm/hive \
  --namespace hive \
  --set host=hive.example.com \
  --set env.HIVE_AUTH_MODE=oidc \
  --set env.HIVE_GOOGLE_ALLOWED_DOMAINS=example.com
```

If you run External Secrets Operator, enable `externalSecrets.enabled`
and provide `storeRef` + `items` pointing at your backend (Vault,
AWS Secrets Manager, 1Password, etc.) in your own values overlay.

### Tuist Production

Tuist's production overlay lives at `infra/helm/hive/values-production.yaml`
and is applied automatically by `.github/workflows/deploy.yml`. It assumes:

- cert-manager, ingress-nginx, external-dns, the CloudNativePG operator.
- External Secrets Operator with a `ClusterSecretStore` named
  `onepassword-hive` pointing at the `hive-k8s-production` vault.
- Hetzner Cloud block storage (`hcloud-volumes`).

Production secrets live in the `hive-k8s-production` 1Password vault.

Create a read-only 1Password service account for that vault, then register a
vault-scoped External Secrets store in the Kubernetes cluster:

```bash
kubectl create namespace onepassword --dry-run=client -o yaml | kubectl apply -f -
kubectl -n onepassword create secret generic onepassword-hive-sa-token \
  --from-literal=token="$(op read 'op://Founders/Service Account Auth Token: hive-k8s-production-sa/credential')" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'YAML' | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword-hive
spec:
  provider:
    onepasswordSDK:
      vault: hive-k8s-production
      auth:
        serviceAccountSecretRef:
          name: onepassword-hive-sa-token
          namespace: onepassword
          key: token
YAML
```

The vault must contain:

- `kubeconfig: hive-production` document, used by GitHub Actions deploys.
- `hive-secret-key-base/password`, generated with `mix phx.gen.secret`.
- `hive-google-oauth/username` and `hive-google-oauth/credential`, holding the
  Google OAuth client ID and secret. Wired into the deployment as
  `HIVE_GOOGLE_CLIENT_ID` and `HIVE_GOOGLE_CLIENT_SECRET`.
- Optional generic OIDC values referenced by the Helm chart.
- `hive-ghcr-pull/notesPlain`, base64 of a Docker config JSON for GHCR pulls.
- `hive-postgres-backup/username` and `hive-postgres-backup/credential`, used by CNPG backups.

<img src="priv/static/images/logo.png" alt="Hive" width="30%" />

# Hive

At Tuist we've reimagined how we shape and build product by leaning into
LLMs and agentic workflows, and Hive is our take on it — built to run
inside our own team and equally to be opened up to the people who use
your products.

Hive is licensed under [MPL-2.0](LICENSE.md). We don't offer it as a
managed service — you can try our own instance at <https://hive.tuist.dev>,
or self-host your own.

## Self-hosting

### Authentication

Hive runs without authentication by default. Set `HIVE_AUTH_MODE=oidc` to gate
all routes behind login. Hive supports one OIDC provider per instance,
selected via `HIVE_OIDC_PROVIDER`:

| `HIVE_OIDC_PROVIDER` | URL slug | Notes                                              |
| -------------------- | -------- | -------------------------------------------------- |
| `google` (preset)    | `google` | Google's URLs are hardcoded; only credentials needed |
| `generic` (default)  | `oidc`   | Bring your own authorize/token/userinfo URLs       |

Shared variables:

- `HIVE_OIDC_CLIENT_ID` — required
- `HIVE_OIDC_CLIENT_SECRET` — required for Google; optional for generic
- `HIVE_OIDC_SCOPES` — optional, defaults to `openid profile email`
- `HIVE_OIDC_ALLOWED_DOMAINS` — optional, comma-separated list of email
  domains to accept (e.g. `tuist.dev`). Enforced on the callback. For
  Google, a single domain also adds Google's `hd=` hint to pre-filter
  the account picker.

Generic-only variables (`HIVE_OIDC_PROVIDER=generic`):

- `HIVE_OIDC_AUTHORIZE_URL` — required
- `HIVE_OIDC_TOKEN_URL` — required
- `HIVE_OIDC_USERINFO_URL` — optional

Callback URL: `/auth/<slug>/callback` on the deployed host
(`/auth/google/callback` or `/auth/oidc/callback`).

#### Setting up Google OAuth

1. Open <https://console.cloud.google.com/apis/credentials> in the Google
   Cloud project you want to use.
2. Configure the OAuth consent screen (User type **Internal** for a
   workspace, **External** otherwise; scopes `openid`, `profile`, `email`).
3. **Create Credentials → OAuth client ID → Web application**.
4. Add the **Authorized redirect URI** for each environment, e.g.
   `https://hive.example.com/auth/google/callback`.
5. Copy the Client ID and Client Secret into `HIVE_OIDC_CLIENT_ID` and
   `HIVE_OIDC_CLIENT_SECRET`, and set `HIVE_OIDC_PROVIDER=google`.

### Deployment

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
  --from-literal=HIVE_OIDC_CLIENT_ID="..." \
  --from-literal=HIVE_OIDC_CLIENT_SECRET="..."

helm upgrade --install hive infra/helm/hive \
  --namespace hive \
  --set host=hive.example.com \
  --set env.HIVE_AUTH_MODE=oidc \
  --set env.HIVE_OIDC_PROVIDER=google \
  --set env.HIVE_OIDC_ALLOWED_DOMAINS=example.com
```

If you run External Secrets Operator, enable `externalSecrets.enabled`
and provide `storeRef` + `items` pointing at your backend (Vault,
AWS Secrets Manager, 1Password, etc.) in your own values overlay.

### Tuist's production setup

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
  `HIVE_OIDC_CLIENT_ID` and `HIVE_OIDC_CLIENT_SECRET` (with
  `HIVE_OIDC_PROVIDER=google` set in the production overlay).
- `hive-ghcr-pull/notesPlain`, base64 of a Docker config JSON for GHCR pulls.
- `hive-postgres-backup/username` and `hive-postgres-backup/credential`, used by CNPG backups.

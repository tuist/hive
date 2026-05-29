<p align="center">
  <img src="priv/static/images/logo.png" alt="Hive" width="20%" />
</p>

# Hive

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
  --from-literal=HIVE_GOOGLE_CLIENT_SECRET="..."

helm upgrade --install hive infra/helm/hive \
  --namespace hive \
  --set host=hive.example.com \
  --set env.HIVE_VISIBILITY=private \
  --set env.HIVE_GOOGLE_ALLOWED_DOMAINS=example.com
```

If you run External Secrets Operator, enable `externalSecrets.enabled`
and provide `storeRef` + `items` pointing at your backend (Vault,
AWS Secrets Manager, 1Password, etc.) in your own values overlay.

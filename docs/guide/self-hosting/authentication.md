## Authentication

Hive's login is available regardless of visibility so administrators can
sign in to a public instance. Authentication is delegated to
[Ueberauth] + [ueberauth_oidcc]; any number of providers can be enabled
simultaneously and will appear as buttons on the login screen.

[Ueberauth]: https://github.com/ueberauth/ueberauth
[ueberauth_oidcc]: https://github.com/erlef/ueberauth_oidcc

## Google

Set these environment variables:

- `HIVE_GOOGLE_CLIENT_ID`
- `HIVE_GOOGLE_CLIENT_SECRET`
- `HIVE_GOOGLE_ALLOWED_DOMAINS` (optional, comma-separated list of email
  domains to accept; for example `tuist.dev`).

When a single domain is set, the authorize redirect also includes
Google's `hd=` hint to pre-filter the account picker. The allowlist is
enforced on the callback regardless.

Callback URL: `/auth/google/callback` on the deployed host.

### Setting up Google OAuth

1. Open <https://console.cloud.google.com/apis/credentials> in the
   Google Cloud project you want to use.
2. Configure the OAuth consent screen (User type **Internal** for a
   workspace, **External** otherwise; scopes `openid`, `profile`,
   `email`).
3. **Create Credentials → OAuth client ID → Web application**.
4. Add the **Authorized redirect URI** for each environment, e.g.
   `https://hive.example.com/auth/google/callback`.
5. Copy the Client ID and Client Secret into `HIVE_GOOGLE_CLIENT_ID`
   and `HIVE_GOOGLE_CLIENT_SECRET`.

## Generic OpenID Connect

Any OIDC provider with a `.well-known/openid-configuration` endpoint:

- `HIVE_OIDC_ISSUER`: the issuer base URL. Hive's auth client discovers
  authorize/token/userinfo endpoints from
  `<issuer>/.well-known/openid-configuration`.
- `HIVE_OIDC_CLIENT_ID`
- `HIVE_OIDC_CLIENT_SECRET` (optional)
- `HIVE_OIDC_DISPLAY_NAME` (optional, label on the login button;
  defaults to "Identity provider")
- `HIVE_OIDC_ALLOWED_DOMAINS` (optional, comma-separated allowlist)

Callback URL: `/auth/oidc/callback` on the deployed host.

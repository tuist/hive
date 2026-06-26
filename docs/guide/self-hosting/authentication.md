## Authentication

Hive's login is available regardless of visibility so administrators can
sign in to a public instance. Configure one or more identity providers
and Hive shows each provider as a login option. Optional domain
allowlists are enforced after the provider returns the user's verified
email address.

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

### Setting up Google OAuth 2.0

1. Open <https://console.cloud.google.com/apis/credentials> in the
   Google Cloud project you want to use.
2. Configure the [OAuth 2.0](https://oauth.net/2/) consent screen
   (User type **Internal** for a
   workspace, **External** otherwise; scopes `openid`, `profile`,
   `email`).
3. **Create Credentials → OAuth 2.0 client ID → Web application**.
4. Add the **Authorized redirect URI** for each environment, for example
   `https://hive.example.com/auth/google/callback`.
5. Copy the Client ID and Client Secret into `HIVE_GOOGLE_CLIENT_ID`
   and `HIVE_GOOGLE_CLIENT_SECRET`.

## Generic OpenID Connect

Any [OpenID Connect](https://openid.net/developers/how-connect-works/)
provider with a `.well-known/openid-configuration` endpoint:

- `HIVE_OIDC_ISSUER`: the issuer base URL. Hive's auth client discovers
  authorize/token/userinfo endpoints from
  `<issuer>/.well-known/openid-configuration`.
- `HIVE_OIDC_CLIENT_ID`
- `HIVE_OIDC_CLIENT_SECRET` (optional)
- `HIVE_OIDC_DISPLAY_NAME` (optional, label on the login button;
  defaults to "Identity provider")
- `HIVE_OIDC_ALLOWED_DOMAINS` (optional, comma-separated allowlist)

Callback URL: `/auth/oidc/callback` on the deployed host.

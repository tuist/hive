# Authentication

Hive's login is available regardless of visibility so administrators can
sign in to a public instance. Configure one or more identity providers
and Hive shows each provider as a login option. Optional domain
allowlists are enforced after the provider returns the user's verified
email address.

Hive supports two provider paths out of the box. Use Google when your
team signs in with Google Workspace. Use generic OpenID Connect
([OIDC](https://openid.net/developers/how-connect-works/)) when your
identity provider publishes a discovery document.

## Google

Configure Google when you want Hive to use the same accounts your team
already uses for Google Workspace. Set these environment variables:

- [`HIVE_GOOGLE_CLIENT_ID`](/reference/configuration#hive_google_client_id)
- [`HIVE_GOOGLE_CLIENT_SECRET`](/reference/configuration#hive_google_client_secret)
- [`HIVE_GOOGLE_ALLOWED_DOMAINS`](/reference/configuration#hive_google_allowed_domains)
  (optional, comma-separated list of email domains to accept; for
  example `tuist.dev`).

When a single domain is set, the authorize redirect also includes
Google's `hd=` hint to pre-filter the account picker. The allowlist is
enforced on the callback regardless.

Callback address: `/auth/google/callback` on the deployed host.

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
5. Copy the Client ID and Client Secret into
   [`HIVE_GOOGLE_CLIENT_ID`](/reference/configuration#hive_google_client_id) and
   [`HIVE_GOOGLE_CLIENT_SECRET`](/reference/configuration#hive_google_client_secret).

## Generic OpenID Connect

Configure generic OpenID Connect when your identity provider is not
Google but exposes a `.well-known/openid-configuration` endpoint. Set
these environment variables:

- [`HIVE_OIDC_ISSUER`](/reference/configuration#hive_oidc_issuer): the issuer
  base address. Hive's auth client discovers authorize/token/userinfo
  endpoints from
  `<issuer>/.well-known/openid-configuration`.
- [`HIVE_OIDC_CLIENT_ID`](/reference/configuration#hive_oidc_client_id)
- [`HIVE_OIDC_CLIENT_SECRET`](/reference/configuration#hive_oidc_client_secret)
  (optional)
- [`HIVE_OIDC_DISPLAY_NAME`](/reference/configuration#hive_oidc_display_name)
  (optional, label on the login button; defaults to "Identity provider")
- [`HIVE_OIDC_ALLOWED_DOMAINS`](/reference/configuration#hive_oidc_allowed_domains)
  (optional, comma-separated allowlist)

Callback address: `/auth/oidc/callback` on the deployed host.

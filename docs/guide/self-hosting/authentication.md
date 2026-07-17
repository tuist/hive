# Authentication

Hive can show one or more sign-in providers. Configure the providers your
organization already uses, and Hive presents each configured option on
the login page.

The login page remains available on public instances so administrators
can sign in. On private instances, configure and test at least one
provider before changing `HIVE_VISIBILITY` to `private`.

## Google

Use Google for organizations that sign in with Google Workspace.

Set:

- [`HIVE_GOOGLE_CLIENT_ID`](/reference/configuration#hive_google_client_id)
- [`HIVE_GOOGLE_CLIENT_SECRET`](/reference/configuration#hive_google_client_secret)
- [`HIVE_GOOGLE_ALLOWED_DOMAINS`](/reference/configuration#hive_google_allowed_domains)
  to an optional comma-separated list of accepted email domains

Create a web application credential in the
[Google Cloud credentials console](https://console.cloud.google.com/apis/credentials)
and add this authorized redirect address:

```text
https://hive.example.com/auth/google/callback
```

Request the `openid`, `profile`, and `email` scopes. For a single Google
Workspace organization, use an internal consent screen when available.

When one allowed domain is configured, Hive also preselects it in the
Google account picker. Hive still validates the verified email after
sign-in.

## GitHub

Use GitHub sign-in when users should authenticate with their GitHub
accounts. This sign-in application is separate from the
[GitHub App used for repository access](./github).

Set:

- [`HIVE_GITHUB_CLIENT_ID`](/reference/configuration#hive_github_client_id)
- [`HIVE_GITHUB_CLIENT_SECRET`](/reference/configuration#hive_github_client_secret)
- [`HIVE_GITHUB_ALLOWED_DOMAINS`](/reference/configuration#hive_github_allowed_domains)
  to an optional comma-separated list of accepted email domains

Create an app that uses Open Authorization
([OAuth 2.0](https://oauth.net/2/)) under the
[GitHub developer settings](https://github.com/settings/developers).
GitHub calls this an OAuth App. Use your Hive address as the homepage and
add this authorization callback:

```text
https://hive.example.com/auth/github/callback
```

Hive requests access to the user's email address so it can apply the
configured domain rules and connect the identity to the correct account.

## Generic OpenID Connect

Use generic
[OpenID Connect](https://openid.net/developers/how-connect-works/) when
your identity provider publishes a discovery document.

Set:

- [`HIVE_OIDC_ISSUER`](/reference/configuration#hive_oidc_issuer) to the
  issuer address
- [`HIVE_OIDC_CLIENT_ID`](/reference/configuration#hive_oidc_client_id)
- [`HIVE_OIDC_CLIENT_SECRET`](/reference/configuration#hive_oidc_client_secret)
  when required by the provider
- [`HIVE_OIDC_DISPLAY_NAME`](/reference/configuration#hive_oidc_display_name)
  to the label shown on the login button
- [`HIVE_OIDC_ALLOWED_DOMAINS`](/reference/configuration#hive_oidc_allowed_domains)
  to an optional comma-separated list of accepted email domains

Register this callback with the provider:

```text
https://hive.example.com/auth/oidc/callback
```

The issuer must expose its discovery document at
`<issuer>/.well-known/openid-configuration`.

## Mobile application

The Hive mobile application starts by asking for the address of the Hive
deployment. It discovers the deployment's authorization endpoints and
registers that installation as a public client through Open Authorization
2.0 ([OAuth 2.0](https://oauth.net/2/)) Dynamic Client Registration, as
defined by Request for Comments 7591
([RFC 7591](https://www.rfc-editor.org/rfc/rfc7591)).
Operators do not need to create or distribute a mobile client secret.

The application opens the system browser for sign-in and returns through
the `dev.tuist.hive://oauth2redirect` application address. Authorization
codes are protected with Proof Key for Code Exchange
as defined by Request for Comments 7636
([RFC 7636](https://www.rfc-editor.org/rfc/rfc7636)), and Hive requires it for
every dynamically registered public client.

The application requests the `mobile` scope for the protected resource at
`https://hive.example.com/api/v1`. That resource offers read-only access to
the signed-in account, visible Forage items, visible specs, visible Drops, and published
Drops weekly digests. It follows
the same role and visibility rules as the dashboard.

The public application programming interface
([API](https://developer.mozilla.org/en-US/docs/Glossary/API)) contract is
available at `/api/openapi.json` in the OpenAPI format. This document
describes the versioned `/api/v1` routes, query parameters, response shapes,
and authorization flow used by both native applications.

After sign-in, the native application stores the renewable session in the
platform's secure credential store. It refreshes that session when the
application launches and before an access token expires. Signing out revokes
the renewable token on Hive and removes the local credentials.

Production deployments must use an `https` Hive address. Plain `http`
addresses are accepted only for loopback development addresses so the
native applications can be exercised against a local Hive server.

## Test before requiring sign-in

After restarting Hive:

1. Open `/login` in a private browser window.
2. Confirm that every configured provider appears once.
3. Sign in and verify that Hive returns to the dashboard.
4. Test an account outside any provider allowlist and confirm that it is
   rejected.
5. Only then set `HIVE_VISIBILITY=private` if the instance should require
   sign-in.

Authentication decides who can sign in. [Authorization](./authorization)
decides what each signed-in account can see and change.

---
description: Connect Hive's native clients to a self-hosted instance and understand their read-only API access.
---

# Native apps

Hive's native clients connect to a deployed Hive instance so people can follow
product work away from the dashboard. Android, iOS, and macOS application
packages are published with [Hive application releases](https://github.com/tuist/hive/releases).

## Connect an app

1. Install a package for your platform from the latest application release.
2. Enter the public HTTPS address of your Hive instance when the app asks for
   its server address. Do not add `/api/v1` to the address.
3. Continue in the system browser and sign in with one of the providers enabled
   on that instance.
4. Review the requested access and approve the connection.
5. Return to the app. It stores the renewable session in the platform's secure
   credential store and refreshes it when needed.

Production instances must use HTTPS. Plain HTTP is accepted only for loopback
development addresses.

## What the apps can read

The native clients use Hive's versioned, read-only API. Depending on the
client and granted scopes, they can read:

- The signed-in account.
- Visible Forage items.
- Visible specs.
- Visible Drops and weekly digests.
- Visible errors.

The same role and visibility rules apply in the dashboard and the native apps.
Private or organization-only content is not made public by connecting a client.

## API discovery

The app discovers the authorization server and protected resource metadata from
the Hive address. Operators do not need to create a client secret: native apps
use Open Authorization 2.0 Dynamic Client Registration and Proof Key for Code
Exchange.

The complete API contract is available at
[`/api/openapi.json`](https://hive.example.com/api/openapi.json) on each Hive
instance. The [API reference](/reference/api) explains the mobile endpoints,
scopes, and discovery addresses. Replace `hive.example.com` in the link with
your own host.

## Troubleshooting

- Confirm that the address is the Hive origin, for example
  `https://hive.example.com`, not a dashboard path.
- Confirm that the instance is reachable over HTTPS and that its certificate is
  trusted by the device.
- Open `/ready` in a browser to check that Hive can reach its database.
- If a provider is missing from the browser login page, review the provider
  settings in the [authentication guide](./authentication).
- If content is missing after sign-in, check the account's role and the
  visibility of the resource in [authorization](./authorization).

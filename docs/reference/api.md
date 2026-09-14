# Application programming interface

Hive exposes two JSON application programming interfaces
([APIs](https://en.wikipedia.org/wiki/API): the Flight API for operational
integrations and the versioned mobile API for native clients. Both use OAuth
2.0 bearer tokens, but they have different resources and scopes.

The complete OpenAPI document is available at `/api/openapi.json` on every Hive
instance. It is the authoritative source for response fields and authorization
requirements.

## Authenticate

The interface uses Open Authorization
([OAuth 2.0](https://oauth.net/2/)) bearer tokens. Clients can discover the
authorization server and protected-resource metadata at:

```text
/.well-known/oauth-authorization-server
/.well-known/oauth-protected-resource/api
```

Request the `api` scope for the `https://hive.example.com/api` resource,
replacing the host with the Hive instance address. Flight access still follows
the signed-in account's role, so collaborators receive a forbidden response.

## Flight endpoints

| Method | Path | Behavior |
|---|---|---|
| `GET` | `/api/flights` | Lists Flights with their Forage relation and outcome. Portable sessions are omitted from list results. |
| `GET` | `/api/flights/:id` | Returns one Flight, including its source metadata and portable agent session. |

The list endpoint accepts `q`, `status`, `objective`, `outcome`, `runner`,
`repository`, `page`, and `page_size` query parameters. Page size defaults to
20 and cannot exceed 100.

For example:

```bash
curl \
  --header "Authorization: Bearer $HIVE_ACCESS_TOKEN" \
  "https://hive.example.com/api/flights?status=succeeded&page_size=20"
```

Responses use a `data` field. List responses also include `pagination` with the
current page, total count, total pages, and previous or next page availability.

One Flight includes its identifier, execution status, objective, objective
outcome, trigger, optional parent Flight, runner, repository, related Forage
item, original input, result or error, requester, timestamps, dashboard path,
and optional session. The session contains the model and agent identifiers,
source repository metadata, and messages captured during execution.

Clients that use the
[Model Context Protocol](https://modelcontextprotocol.io/) can access the same
resource with `list_flights`, `get_flight`, and
`start_forage_item_flight`. `start_grafana_alert_flight` remains available for
Grafana-specific clients and accepts the same objective values.

## Mobile API

Native clients use the `/api/v1` resource. Its protected-resource metadata is
available at `/.well-known/oauth-protected-resource/api/v1`. Request the
`mobile` umbrella scope, or the narrower scope for each resource the client
needs:

| Scope | Resource |
|---|---|
| `mobile.me.read` | `GET /api/v1/me` |
| `mobile.forage.read` | `GET /api/v1/forage` and `GET /api/v1/forage/:item_id` |
| `mobile.specs.read` | `GET /api/v1/specs` and `GET /api/v1/specs/:number` |
| `mobile.drops.read` | `GET /api/v1/drops`, `GET /api/v1/drops/:number`, and digest endpoints |
| `mobile.errors.read` | `GET /api/v1/errors` and `GET /api/v1/errors/:id` |

The mobile API is read-only. It follows the signed-in account's role and the
resource's visibility, so a token cannot reveal private content that the
account could not see in the dashboard. The [native apps guide](/guide/self-hosting/mobile)
describes the browser-based authorization flow and supported clients.

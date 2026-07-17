# Application programming interface

Hive exposes a JSON application programming interface
([API](https://en.wikipedia.org/wiki/API)) for integrations that need Flight
history or continuation context outside the dashboard.

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

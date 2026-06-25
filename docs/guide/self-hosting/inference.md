## Inference relay

Hive can expose an OpenAI-compatible inference relay for automation that
already knows how to talk to that standard provider surface. Repositories and
workflows point at Hive with a Hive token, and Hive decides which upstream
provider and model should handle the request.

This gives operators one place to retarget a model for cost, latency, or
quality without changing every repository. It also gives them a more granular
usage and cost view because every request is attributed to the profile and
token that made it.

## Configure upstream providers

Open **Ops → Inference → Providers** as an instance admin and create a
provider with:

- **Provider key**: the stable key profiles will reference, such as
  `fireworks-ai`. Use the provider identifier from
  [models.dev](https://models.dev).
- **Endpoint**: the upstream base address, such as
  `https://api.fireworks.ai/inference/v1`.
- **Credential**: the provider token. Hive encrypts this value and never shows
  it again after saving.
- **Timeout in milliseconds**: how long Hive should wait for upstream
  responses.

Model pricing is configured on each profile in the dashboard so operators can
update rates without redeploying Hive.

Environment-backed providers are also supported for self-hosted deployments
that prefer immutable runtime configuration. For a single upstream provider,
set:

```bash
HIVE_INFERENCE_UPSTREAM_ID=fireworks-ai
HIVE_INFERENCE_UPSTREAM_BASE_URL=https://api.fireworks.ai/inference/v1
HIVE_INFERENCE_UPSTREAM_API_KEY=provider-token
```

For multiple upstream providers, set `HIVE_INFERENCE_PROVIDERS` to a
JavaScript Object Notation ([JSON](https://www.json.org/json-en.html)) object:

```bash
HIVE_INFERENCE_PROVIDERS='{
  "fireworks-ai": {
    "base_url": "https://api.fireworks.ai/inference/v1",
    "api_key": "provider-token"
  },
  "openai": {
    "base_url": "https://api.openai.com/v1",
    "api_key": "provider-token"
  }
}'
```

The dashboard exposes **Ops → Inference → Providers** so instance admins can
create runtime providers, review environment-backed providers, see whether a
credential is present, and check which profiles reference each provider. Secret
values are never shown.

## Track usage and cost

Each successful relay response creates a usage record tied to both the profile
and the token that made the request. Hive stores:

- input token count
- output token count
- total token count
- upstream status
- estimated United States dollar cost

The profile page aggregates those rows for the selected period and shows input
tokens, output tokens, estimated cost, and a trend chart. Token rows also show
their own usage and cost for the same period. Each token has a detail page with
the same widgets and chart scoped to that token.

## Create a profile and token

After migrations have run, open **Ops → Inference → Profiles** as an instance
admin.

Create a profile with:

- **Profile name**: the stable model name repositories will request, such as
  `repository-review`.
- **Upstream provider**: the provider key from **Ops → Inference → Providers**
  or the environment configuration, such as `fireworks-ai`.
- **Upstream model**: the models.dev `provider/model` identifier, such as
  `fireworks-ai/accounts/fireworks/models/kimi-k2p5` or
  `openai/gpt-4o-mini`. The provider prefix must match the selected upstream
  provider. Hive strips that prefix before forwarding the request to the
  upstream provider.
- **Input cost per million tokens** and **Output cost per million tokens**:
  optional United States dollar prices for the upstream model. Hive uses these
  values to estimate cost after each relay response reports usage.

Then create a token under that profile. Hive prints the token once in the
dashboard. Store it in the repository secret manager before dismissing it;
Hive stores only a hash and cannot show the token again.

::: tip Token attribution
Tokens are the attribution boundary for relay usage. Create one token per
repository, workflow, team, or automation boundary that should have its own
usage and cost breakdown. The profile keeps the stable model routing, while
each token gives operators a separate usage trail and revocation point.
:::

To retarget repositories later, edit the profile's upstream provider or model.
Existing tokens keep working because they are bound to the stable profile name.
Disable a profile to stop all of its tokens, or open a token detail page to
revoke that token.

## Connect clients

Open a profile detail page to copy the client configuration for that profile.
Hive shows the base address, model name, authorization header shape, and a
client snippet that can be adapted to any OpenAI-compatible client.

The relay exposes:

- `GET /v1/models`: returns the one model allowed by the token.
- `POST /v1/chat/completions`: validates the requested model, rewrites it to
  the configured upstream model, and forwards the response.

# Model gateway

Hive can act as a model gateway for automation and agentic workflows.
Calling it a gateway is intentional: Hive is not only forwarding traffic.
It authenticates Hive tokens, routes requests through profiles, hides
upstream provider credentials from repositories, and records usage and
cost.

For client traffic, repositories and workflows point at Hive with a Hive
token. Hive decides which upstream provider and model should handle the
request. For agentic workflows inside Hive, instance admins can mark one
profile as Hive's inference profile so Hive calls its own gateway instead
of depending on launch-time model configuration.

This gives operators one place to retarget a model for cost, latency, or
quality without changing every repository or workflow. It also gives them
a more granular usage and cost view because every client request is
attributed to the profile and token that made it.

The client-facing gateway supports chat completions, streaming chat
completions, and embeddings. All of them use the same profile model
rewriting, provider credential hiding, token attribution, and cost
tracking.

## Configure model providers

Open **Ops -> Inference -> Providers** as an instance admin and create a
provider with:

- **Provider key**: the stable key profiles will reference, such as
  `togetherai` or `openai`.
- **Endpoint**: the upstream base address, such as
  `https://api.together.ai/v1`.
- **Credential**: the provider token. Hive encrypts this value and never
  shows it again after saving.
- **Timeout in milliseconds**: how long Hive should wait for upstream
  responses.

Model pricing is configured on each profile in the dashboard so
operators can update rates without redeploying Hive.

Environment-backed providers are also supported for self-hosted
deployments that prefer immutable runtime configuration. For a single
upstream provider, set the single-provider variables from the
[configuration reference](/reference/configuration#model-gateway):

```bash
HIVE_INFERENCE_UPSTREAM_ID=togetherai
HIVE_INFERENCE_UPSTREAM_BASE_URL=https://api.together.ai/v1
HIVE_INFERENCE_UPSTREAM_API_KEY=provider-token
```

For multiple upstream providers, set
[`HIVE_INFERENCE_PROVIDERS`](/reference/configuration#hive_inference_providers)
to a JavaScript Object Notation
([JSON](https://www.json.org/json-en.html)) object:

```bash
HIVE_INFERENCE_PROVIDERS='{
  "togetherai": {
    "base_url": "https://api.together.ai/v1",
    "api_key": "provider-token"
  },
  "openai": {
    "base_url": "https://api.openai.com/v1",
    "api_key": "provider-token"
  }
}'
```

The dashboard exposes **Ops -> Inference -> Providers** so instance
admins can create runtime providers, review environment-backed
providers, see whether a credential is present, and check which profiles
reference each provider. Secret values are never shown.

## Agentic workflows

Hive's agentic features call a
[large language model](https://en.wikipedia.org/wiki/Large_language_model).
The preferred setup is to create a normal gateway profile, then mark it
as **Use for Hive inference** on the profile form. Hive generates a
Hive-owned token for that profile, stores the token value encrypted, and
uses the profile through `/inference/v1` just like any other
OpenAI-compatible client. Usage and cost are attributed to that profile
and token.

If no profile is marked for Hive inference, Hive falls back to the
deployment-wide model provider configured through the
[configuration reference](/reference/configuration#agent-model-provider).
When neither path is configured, agentic features stay dormant and the
rest of Hive runs normally.

When model configuration is present, Hive starts the agentic workflows
automatically. There is no separate feature flag for enabling agentic
behavior.

Hive currently uses agents for:

- Domain evolution: when new forage items, specs, GitHub issues, or
  Grafana alerts arrive, Hive queues a debounced evolution job. A
  periodic job runs as well. The agent reviews recent work signals,
  current projects, and current domains, then proposes only create or
  update changes. New domains are linked to the projects named by the
  supporting work items. Hive applies those changes through normal
  validation and skips suggestions that are too generic, too specific,
  or outside Tuist's business domains. Hive records the fingerprint of
  every evaluated input, including evaluations that produce no changes,
  so periodic and event-driven jobs do not evaluate unchanged evidence
  again.
- Spec revision summaries: whenever a spec is edited after its first
  draft, Hive queues a job that asks the agent to describe what changed
  between the previous and the new revision. The summary appears in the
  draft history on the spec page. A scheduled sweeper also backfills
  revisions whose summary is still missing, spawning one worker job per
  revision so failures retry independently. The model receives a compact
  line diff instead of two complete copies of the spec and runs as one
  bounded request without loading repository instructions. When no model
  provider is configured, the history falls back to a counts-based
  heuristic.
- Spec review requests: when a spec author or editor asks for another
  review, Hive asks an agent to turn the current spec and latest
  revision into a concise Slack message with focused review prompts. The
  current body is sent once alongside the latest revision metadata. The
  Slack notification still posts with a deterministic fallback when no
  model provider is configured.
- Slack thread replies and forage capture: when Hive's Slack bot is
  `@`-mentioned, Hive queues a job that reads the thread context and
  asks the agent to draft a short reply, posted back in the same thread.
  If the requester is linked to a Hive user and asks Hive to capture
  work, the agent can create a forage item through the configured intake
  destination from **Ops -> Forage**. When that destination creates
  GitHub issues, Hive shows the agent the repository labels that already
  exist so it can pick matching labels and Hive can validate them before
  issue creation. Long threads retain the root message, the triggering
  mention, and the newest messages within a fixed context budget; the
  prompt tells the agent how many earlier messages were omitted. Label
  descriptions and individual messages are bounded as well. When no
  model provider is configured, the bot replies with a setup note. See
  [Slack](./slack) for the workspace install flow.
- GitHub issue domain classification: each time the syncer sees a new
  issue in a connected project repository or notices that an issue's
  title or body changed, Hive queues a job that asks the agent which
  domains the issue actually belongs to. The candidates are the domains
  attached to the issue's repository, so the answer is always a subset of
  that set. The dashboard renders the domain badges from this
  classification, not from the repository's domain membership. A
  scheduled sweeper also re-classifies any cached issue still missing a
  classification, so rows that existed before classification shipped or
  that hit a transient model-provider failure recover later. Billing,
  quota, suspension, and rate-limit provider responses keep the worker
  scheduled with a backoff instead of producing repeated failure events.
  When no model provider is configured, each issue is linked to every
  domain attached to its repository.
- Drop item generation: each GitHub release body is treated as an
  envelope, not as a drop. Hive deterministically fetches the public web
  addresses referenced by the release and recursively follows addresses
  discovered in that evidence, up to 50 fetched references in total,
  before making one model request. The agent receives the fetched issues,
  pull requests, changelog entries, and docs together and returns one drop
  item per user-facing improvement that actually landed. A sync evaluates
  at most five unseen or edited releases per repository, then continues the
  historical backlog on the next run. Successful, ignored, and
  provider-rejected evaluations are durable; transient failures use
  exponential backoff. An edited release is evaluated again only when its
  content fingerprint changes, and the complete bounded evidence set is
  re-evaluated so new context can change item grouping. When no model
  provider is configured, GitHub release drop generation is skipped so
  release envelopes do not pollute the drops timeline.
- Drop domain classification: after a drop item exists, Hive queues a
  job that asks the agent which domains the drop belongs to. When no
  model provider is configured, each drop is linked to every domain
  associated with the release repository's project.

Structured agent operations have a three-turn default ceiling. Individual
workflows can lower that ceiling when they need only one response. This
prevents a malformed or unresponsive run from repeatedly resending its
accumulated conversation while preserving tool-using workflows that need a
small follow-up exchange.

## Agent model provider

Open **Ops -> Inference -> Profiles**, create a chat-completion profile,
and enable **Use for Hive inference**. Only one enabled profile can hold
that role at a time. Marking another profile moves Hive's inference role
to the new profile, so operators can retarget Hive's own agents without
redeploying.

You can also mark one profile as **Use for Hive embeddings**. That gives
Hive a separate OpenAI-compatible embedding profile for workflows that
need vectors. Use an upstream embedding model for that profile.

The environment variables below remain available as a fallback for
deployments that prefer immutable launch-time model configuration:

- [`HIVE_LLM_API_KEY`](/reference/configuration#hive_llm_api_key): the
  provider key. When unset and no Hive inference profile is selected,
  every agentic feature is disabled.
- [`HIVE_LLM_MODEL`](/reference/configuration#hive_llm_model): the model
  in `provider:model_id` form, for example
  `anthropic:claude-haiku-4-5`. Required when
  [`HIVE_LLM_API_KEY`](/reference/configuration#hive_llm_api_key) is set.
- [`HIVE_LLM_BASE_URL`](/reference/configuration#hive_llm_base_url):
  optional endpoint override. Use it to point at a compatible provider
  that is not reachable at its vendor's default address.

Any provider supported by [ReqLLM](https://hexdocs.pm/req_llm) works.
ReqLLM's catalog is sourced from [models.dev](https://models.dev), so the
`provider:model_id` strings you can put in
[`HIVE_LLM_MODEL`](/reference/configuration#hive_llm_model) are exactly
the identifiers listed there.

For an OpenAI-compatible gateway such as Together.ai, set the provider
prefix to `openai:`, the model identifier to whatever the gateway
expects, and
[`HIVE_LLM_BASE_URL`](/reference/configuration#hive_llm_base_url) to its
endpoint:

```bash
HIVE_LLM_MODEL=openai:MiniMaxAI/MiniMax-M3
HIVE_LLM_BASE_URL=https://api.together.ai/v1
HIVE_LLM_API_KEY=provider-token
```

Prefer an inference profile for Together.ai and other gateways: create a
profile whose upstream provider is `togetherai` and upstream model is
`MiniMaxAI/MiniMax-M3`, then mark it **Use for Hive inference** so Hive
routes its own agents through the gateway and records usage on the
profile.

## Track usage and cost

Each successful gateway response creates a usage record tied to both the
profile and the token that made the request. Hive stores:

- operation type
- input token count
- output token count
- total token count
- upstream status
- estimated United States dollar cost

For embedding responses, Hive records the provider-reported prompt or
input tokens as input tokens, records zero output tokens, and estimates
cost from the profile's input price.

The profile page aggregates those rows for the selected period and shows
input tokens, output tokens, estimated cost, and a trend chart. Token
rows also show their own usage and cost for the same period. Each token
has a detail page with the same widgets and chart scoped to that token.
Failed upstream responses are not counted toward request, token, or cost
analytics.

## Create a profile and token

After migrations have run, open **Ops -> Inference -> Profiles** as an
instance admin.

Create a profile with:

- **Profile name**: the stable model name repositories will request,
  such as `repository-review`.
- **Upstream provider**: the provider key from **Ops -> Inference ->
  Providers** or the environment configuration, such as `fireworks`.
- **Upstream model**: the model identifier the upstream endpoint
  expects, such as `accounts/fireworks/models/kimi-k2p5` or
  `MiniMaxAI/MiniMax-M3`. For an embedding profile, use the upstream
  embedding model, such as `BAAI/bge-large-en-v1.5`.
- **Input cost per million tokens** and **Output cost per million
  tokens**: optional United States dollar prices for the upstream model.
  Hive uses these values to estimate cost after each gateway response
  reports usage.

Then create a token under that profile. Hive prints the token once in
the dashboard. Store it in the repository secret manager before
dismissing it; Hive stores only a hash and cannot show the token again.

::: tip Token attribution
Tokens are the attribution boundary for gateway usage. Create one token
per repository, workflow, team, or automation boundary that should have
its own usage and cost breakdown. The profile keeps the stable model
routing, while each token gives operators a separate usage trail and
revocation point.
:::

To retarget repositories later, edit the profile's upstream provider or
model. Existing tokens keep working because they are bound to the stable
profile name. Disable a profile to stop all of its tokens, or open a
token detail page to revoke that token.

## Connect clients

Open a profile detail page to copy the client configuration for that
profile. Hive shows the base address, model name, authorization header
shape, and a client snippet that can be adapted to any OpenAI-compatible
client.

The gateway exposes:

- `GET /inference/v1/models`: returns the one model allowed by the token.
- `POST /inference/v1/chat/completions`: validates the requested model, rewrites
  it to the configured upstream model, and forwards the response.
- `POST /inference/v1/embeddings`: validates the requested model,
  rewrites it to the configured upstream embedding model, forwards the
  response, and records embedding usage.

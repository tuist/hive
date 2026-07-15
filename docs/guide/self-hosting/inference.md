# Model gateway

Hive can give repositories, workflows, and its own language-model
features one stable address for model access. Administrators choose the
upstream provider and model while clients use a Hive profile name and
token.

This lets an organization change providers without updating every
client, keep provider credentials out of repositories, and attribute
usage and estimated cost to each token.

The gateway supports chat completions, streaming chat completions, and
embeddings.

## Set up the gateway

The recommended sequence is provider, profile, token, then client.

### 1. Create a provider

Open **Ops (Operations) → Inference → Providers** and select
**Create provider**.

Provide:

- **Provider key**: a stable internal label such as `openai` or
  `togetherai`.
- **Endpoint**: the provider's OpenAI-compatible base address.
- **Credential**: the provider token. Hive encrypts it and does not show
  it again.
- **Timeout**: how long Hive should wait for the provider.

Self-hosters who prefer launch-time configuration can define providers
with the values under
[Model gateway](/reference/configuration#model-gateway). Dashboard-managed
and environment-managed providers appear in the same provider list.

### 2. Create a profile

Open **Ops (Operations) → Inference → Profiles** and select
**Create profile**.

A profile gives clients a stable model name. Configure:

- **Profile name**: the model name clients will request, such as
  `repository-review`.
- **Upstream provider**: one of the configured provider keys.
- **Upstream model**: the model identifier expected by that provider.
- **Input and output price**: optional United States dollar prices per
  million tokens for cost estimates.

Use a chat model for chat-completion profiles and an embedding model for
embedding profiles.

### 3. Create a token

Open the profile and create a token. Hive shows the token value once.
Copy it into the client or repository secret manager before dismissing
the message.

Create a separate token for each repository, workflow, team, or other
boundary that needs independent usage reporting or revocation. Editing
the profile later retargets every active token without changing the
client configuration.

### 4. Connect a client

The profile page shows the base address, profile name, authorization
header, and a client example. Hive exposes:

- `GET /inference/v1/models`
- `POST /inference/v1/chat/completions`
- `POST /inference/v1/embeddings`

Clients must request the profile name associated with their token. Hive
selects the configured upstream model before forwarding the request.

## Track usage and cost

Each successful request is attributed to its profile and token. Profile
and token pages show request counts, input tokens, output tokens,
estimated cost, and a trend for the selected period.

Embedding requests count provider-reported input tokens and use the
profile's input price. Failed upstream responses are not included in
request, token, or cost totals.

Pricing is an estimate based on the values entered on the profile. Update
those values when the provider changes its rates.

## Agentic workflows

Hive can use one gateway profile for its own language-model features.
Open a chat-completion profile and select **Use for Hive inference**.
Only one enabled profile can hold this role, and moving the role changes
Hive's model without a redeployment.

Hive currently uses language models for:

| Workflow | User-facing outcome |
|---|---|
| Domain evolution | Suggests durable domains and improves domain descriptions from recent product work. |
| Spec review requests | Produces focused Slack review prompts for the latest spec revision. |
| Slack conversations | Replies to mentions and captures requested Forage items. |
| GitHub issue classification | Links mirrored issues to the relevant project domains. |
| Drop generation | Turns release evidence into user-facing shipped improvements. |
| Drop classification | Links shipped improvements to the relevant domains. |
| Weekly Drops digest | Connects the week's public improvements into a narrated edition. |

These workflows start automatically when Hive inference is configured.
When it is not configured, Hive continues to run and uses the documented
non-model behavior for each feature.

Scheduled classification retries only revisit pending work. Permanent
provider rejections, such as invalid credentials or exhausted credit, are
recorded and are not requested again for unchanged source content. A changed
GitHub issue becomes eligible for classification again.

For a separate embedding profile, select **Use for Hive embeddings** on
an embedding-capable profile.

## Launch-time fallback

If no profile is marked for Hive inference, self-hosters can provide
`HIVE_LLM_API_KEY`, `HIVE_LLM_MODEL`, and optionally
`HIVE_LLM_BASE_URL`. See
[Agent model provider](/reference/configuration#agent-model-provider).

The dashboard-managed profile is preferred because it keeps Hive's own
usage visible beside other gateway clients and can be changed without a
deployment.

## Stop or retarget access

- Edit a profile to change its upstream provider or model while keeping
  client configuration stable.
- Disable a profile to stop every token associated with it.
- Revoke one token to stop a single client.
- Move **Use for Hive inference** to another enabled profile to retarget
  Hive's own workflows.

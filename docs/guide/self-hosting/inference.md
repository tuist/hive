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

## Model Context Protocol access

Instance administrators can inspect providers, profiles, tokens, and usage
through [Model Context Protocol](https://modelcontextprotocol.io/) tools:

- `list_inference_providers` returns provider endpoints and configuration
  status, never credentials.
- `list_inference_profiles` returns profile routing and pricing details.
- `list_inference_tokens` returns token metadata, never token values.
- `get_inference_usage` returns request, token, and estimated-cost totals for
  the whole organization, one profile, or one token.

For a custom cost period, pass both `start_at` and `end_at` to
`get_inference_usage`. Each accepts an inclusive ISO 8601 date or datetime;
date-only values cover the whole start or end day. When neither value is
provided, the tool uses the last 30 days.

## Agentic workflows

Hive uses gateway profiles for its own language-model features. Open a
chat-completion profile and select **Use for Hive inference**. Only one enabled
profile can hold this role, and moving the role changes Hive's general model
without a redeployment.

Flights can use a separate model selected with **Use for Hive coding**.
Only one enabled profile can hold the coding role. When no coding profile is
selected, Flights fall back to the general Hive inference profile and then
to the launch-time configuration described below.

Hive currently uses language models for:

| Workflow | User-facing outcome |
|---|---|
| Domain evolution | Suggests durable domains and improves domain descriptions from recent product work. |
| Spec review requests | Produces focused Slack review prompts for the latest spec revision. |
| Slack conversations | Reads the triggering mention with its surrounding thread, streams replies with live status updates, captures requested Forage items, gives unlinked people a direct profile-connection path, and starts objective-specific Flights from Grafana alert threads. |
| GitHub issue classification | Links mirrored issues to the relevant project domains. |
| Forage Flights | Investigates, reproduces, or fixes a Grafana alert or GitHub issue in an isolated repository snapshot, preserves the portable agent session, and returns a pull request or report after a member starts the Flight. |
| Drop generation | Extracts individual, user-facing feature drops from published GitHub releases. Hive supplies release notes and up to six directly referenced GitHub issues or pull requests, never crawling linked webpages. The model receives one turn per release, and the scheduled backlog advances by one release at a time. A release from a project with one domain is linked directly; multi-domain releases use the normal drop classification workflow. |
| Drop classification | Links shipped improvements to the relevant domains. |
| Weekly Drops digest | Connects the week's public improvements into a narrated edition. |
| Error summaries | Posts a scheduled Slack digest of recently observed unresolved errors and highlights up to five issues whose severity, recurrence, or freshness requires special attention. Each highlighted issue shows its project, level, and event count. The model receives only bounded aggregate issue metadata, never raw event payloads. |
| Postmortem semantic retrieval | Stores a durable vector for each published postmortem so related incidents can be found by meaning. |

Most of these workflows start from their scheduled or event-driven trigger
when Hive inference is configured. Flights are different: an organization
member must start each Flight from the Forage item, a Grafana alert thread in
Slack, or a connected client. When inference is not configured, Hive continues
to run and uses the documented non-model behavior for each feature.

Error summaries are disabled by default. Instance administrators can enable
them and change their schedule or Slack channel under **Ops -> Errors**. Changes
take effect at runtime without restarting Hive. The corresponding
[launch-time configuration](/reference/configuration#hive_error_summary_enabled)
provides initial values for a new installation. Hive stores each reporting
period before model generation and stores generated text before posting it. A
delivery retry therefore reuses the stored text, and an empty period uses no
model tokens.

Hive's built-in inference token caps each model response at 1,200 tokens. It
is a final guardrail for workflows using the **Use for Hive inference** profile,
not a replacement for their own durable state and bounded input design.

Flights also require a [sandbox runner](/reference/configuration#coding-runs)
and a GitHub App with permission to write repository contents and pull
requests. Hive calls the selected coding profile through its own gateway and
keeps both the model token and GitHub credential outside the sandbox. The
language model receives coding tools backed by the sandbox, while Hive
publishes any returned changes afterward. Hive includes local microsandbox and
Kubernetes Agent Sandbox providers. The Kubernetes provider uses Condukt's
Kubernetes execution layer for file and command operations while Agent Sandbox
owns isolated pod lifecycle and cleanup. Self-hosters can supply another
provider through the runtime-configurable Condukt sandbox contract.

Scheduled classification retries only revisit pending work. Rejections that
describe the request, such as invalid credentials, are recorded and are not
requested again for unchanged source content. Rejections that describe the
account, such as exhausted credit or a suspended provider, are reconsidered an
hour later, because they say nothing about the item that happened to be in
flight when the account went down. A changed GitHub issue becomes eligible for
classification again.

For a separate embedding profile, select **Use for Hive embeddings** on
an embedding-capable profile.

Postmortems are indexed asynchronously. Hive records the source-content
fingerprint with each vector, so unchanged content is never sent for a second
embedding request. Editing a postmortem creates one new pending index entry;
obsolete jobs exit without making a provider request. Permanent provider
rejections are recorded until the postmortem changes. Very long postmortems are
indexed on their opening sections so they stay searchable instead of exceeding
the embedding model's input limit.

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
- Move **Use for Hive coding** to another enabled profile to retarget Flights
  independently.

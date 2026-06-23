## Agents

Hive's agentic features call an LLM. They share a single provider and
model configured through three environment variables. When no API key
is set, agentic features stay dormant and the rest of Hive runs
normally, so you can deploy without an LLM and turn it on later.

## What Hive uses agents for

When LLM configuration is present, Hive starts the agentic workflows
automatically. There is no separate feature flag for enabling agentic
behavior.

Hive currently uses agents for:

- Domain evolution: when new forage items or specs arrive, Hive queues a
  debounced evolution job. A periodic job runs as well. The agent
  reviews recent work signals and current domains, then proposes only
  create or update changes. Hive applies those changes through normal
  validation and skips suggestions that are too generic, too specific,
  or outside Tuist's business domains.
- Spec revision summaries: whenever a spec is edited after its first
  draft, Hive queues a job that asks the agent to describe what
  changed between the previous and the new revision. The summary
  appears in the draft history on the spec page. A scheduled sweeper
  also backfills revisions whose summary is still missing, spawning one
  worker job per revision so failures retry independently. When no LLM
  is configured, the history falls back to a counts-based heuristic.
- Slack thread replies: when Hive's Slack bot is `@`-mentioned, Hive
  queues a job that reads the thread context and asks the agent to
  draft a short reply, posted back in the same thread. When no LLM is
  configured, the bot stays silent. See [Slack](./slack) for the
  workspace install flow.
- GitHub issue domain classification: each time the syncer sees a new
  issue or notices that an issue's title or body changed, Hive queues a
  job that asks the agent which domains the issue actually belongs to.
  The candidates are the domains attached to the issue's repository, so
  the answer is always a subset of that set. The dashboard renders the
  domain badges from this classification, not from the repository's
  domain membership, so an issue in `tuist/tuist` only appears under
  Cache when its substance is about caching. A scheduled sweeper also
  re-classifies any cached issue still missing a classification, so
  rows that existed before classification shipped or that hit a transient
  LLM failure recover on the next tick. When no LLM is configured, each
  issue is linked to every domain attached to its repository, matching
  pre-classification behaviour.
- Drop item generation: each GitHub release body is treated as an
  envelope, not as a drop. Hive asks an agent to traverse the release
  body's referenced URLs with the URL-fetching tool, collect enough
  context from linked issues, pull requests, changelog entries, or docs,
  and return one drop item per user-facing improvement that actually
  landed. When no LLM is configured, GitHub release drop generation is
  skipped so release envelopes do not pollute the drops timeline.
- Drop domain classification: after a drop item exists, Hive queues a
  job that asks the agent which domains the drop belongs to. When no LLM
  is configured, each drop is linked to every domain associated with
  the release repository's project.

## Configuration

- `HIVE_LLM_API_KEY`: the provider's API key. When unset, every
  agentic feature is disabled.
- `HIVE_LLM_MODEL`: the model in `provider:model_id` form, for
  example `anthropic:claude-haiku-4-5` or
  `fireworks_ai:accounts/fireworks/models/kimi-k2p7-code`. Required when
  `HIVE_LLM_API_KEY` is set.
- `HIVE_LLM_BASE_URL`: optional endpoint override. Use it to point at
  a compatible provider that isn't reachable at its vendor's default
  URL.

## Providers

Any provider supported by [ReqLLM](https://hexdocs.pm/req_llm) works.
ReqLLM's catalog is sourced from [models.dev](https://models.dev), so
the `provider:model_id` strings you can put in `HIVE_LLM_MODEL` are
exactly the IDs listed there. The patterns below are the common ones.

### Anthropic

```bash
HIVE_LLM_API_KEY=sk-ant-...
HIVE_LLM_MODEL=anthropic:claude-haiku-4-5
```

### OpenAI

```bash
HIVE_LLM_API_KEY=sk-...
HIVE_LLM_MODEL=openai:gpt-4o-mini
```

### Fireworks

Fireworks has a native ReqLLM provider. Use Fireworks model IDs in the
canonical `accounts/fireworks/models/<slug>` form:

```bash
HIVE_LLM_API_KEY=fw_...
HIVE_LLM_MODEL=fireworks_ai:accounts/fireworks/models/kimi-k2p7-code
```

For other OpenAI-compatible gateways (vLLM, LiteLLM, Together, etc.),
set the provider prefix to `openai:`, the model id to whatever the
gateway expects, and `HIVE_LLM_BASE_URL` to its endpoint.

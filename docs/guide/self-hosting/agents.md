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

- Meadow evolution: when new forage items or specs arrive, Hive queues a
  debounced evolution job. A periodic job runs as well. The agent
  reviews recent work signals and current meadows, then proposes only
  create or update changes. Hive applies those changes through normal
  validation and skips suggestions that are too generic, too specific,
  or outside Tuist's business domains.
- Spec revision summaries: whenever a spec is edited after its first
  draft, Hive queues a job that asks the agent to describe what
  changed between the previous and the new revision. The summary
  appears in the draft history on the spec page. When no LLM is
  configured, the history falls back to a counts-based heuristic.
- Slack thread replies: when Hive's Slack bot is `@`-mentioned, Hive
  queues a job that reads the thread context and asks the agent to
  draft a short reply, posted back in the same thread. When no LLM is
  configured, the bot stays silent. See [Slack](./slack) for the
  workspace install flow.
- GitHub issue meadow classification: each time the syncer sees a new
  issue or notices that an issue's title or body changed, Hive queues a
  job that asks the agent which meadows the issue actually belongs to.
  The candidates are the meadows attached to the issue's repository, so
  the answer is always a subset of that set. The dashboard renders the
  meadow badges from this classification, not from the repository's
  meadow membership, so an issue in `tuist/tuist` only appears under
  Cache when its substance is about caching. A scheduled sweeper also
  re-classifies any cached issue still missing a classification, so
  rows that existed before classification shipped or that hit a transient
  LLM failure recover on the next tick. When no LLM is configured, each
  issue is linked to every meadow attached to its repository, matching
  pre-classification behaviour.
- Drop release rewriting: when a GitHub release is ingested as a drop,
  Hive queues a job that asks the agent to rewrite the release notes
  into a user-facing markdown changelog. The agent resolves any issues
  and pull requests referenced in the release body so it can describe
  what changed in product terms without leaking pull-request numbers,
  contributor handles, or internal labels. Re-runs are skipped while a
  rewritten body is already on the drop; if the upstream release notes
  change, the rewrite is invalidated and re-runs on the next sync.
  When no LLM is configured, drops keep showing the raw release notes
  unchanged.

## Configuration

- `HIVE_LLM_API_KEY`: the provider's API key. When unset, every
  agentic feature is disabled.
- `HIVE_LLM_MODEL`: the model in `provider:model_id` form, for
  example `anthropic:claude-haiku-4-5` or
  `openai:accounts/fireworks/models/kimi-k2p5`. Required when
  `HIVE_LLM_API_KEY` is set.
- `HIVE_LLM_BASE_URL`: optional endpoint override. Use it to point at
  a compatible provider that isn't reachable at its vendor's default
  URL (for example, Fireworks via the OpenAI-compatible API).

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

### Fireworks (OpenAI-compatible)

Fireworks exposes its catalog through an OpenAI-compatible endpoint, so
you point ReqLLM at the OpenAI provider and override the base URL:

```bash
HIVE_LLM_API_KEY=fw_...
HIVE_LLM_MODEL=openai:accounts/fireworks/models/kimi-k2p5
HIVE_LLM_BASE_URL=https://api.fireworks.ai/inference/v1
```

The same shape works for any other OpenAI-compatible gateway (vLLM,
LiteLLM, Together, etc.): set the provider prefix to `openai:`, the
model id to whatever the gateway expects, and `HIVE_LLM_BASE_URL` to
its endpoint.

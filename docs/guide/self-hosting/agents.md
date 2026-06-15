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

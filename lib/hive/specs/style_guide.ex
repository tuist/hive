defmodule Hive.Specs.StyleGuide do
  @moduledoc """
  House style for writing Hive specs and Tuist RFCs.

  Distilled from the Tuist RFC corpus on community.tuist.dev and the
  review feedback patterns we see in practice. Surfaced to MCP clients
  via the `write_spec` prompt and reusable by any future internal agent
  that drafts specs.
  """

  @body """
  # Writing a Hive spec

  Hive specs and Tuist RFCs (community.tuist.dev) share conventions. A
  spec is a public, reviewed contract for a non-trivial change.

  ## Altitude

  A spec answers Why, then What, then how it feels from outside. It does
  not show how it is built.

  Belongs in the spec:
  - Why the change matters in concrete operator or consumer terms (a
    regression pattern, a recurring failure mode, a compliance boundary,
    a fixed-pool cost). Not abstract framing.
  - Current state, factually: what exists, what does not, with numbers
    where they matter ("three Supabase projects", "274 migrations",
    "~2 VMs per Mac mini").
  - Prior art with sources named. What we take, what we discard.
  - The proposed surface as a contract: API verbs, CLI subcommands, MCP
    tool names, event envelope shape, route table, IO format. Show
    inputs and outputs.
  - Goals, numbered, each a single sentence answering "what must do this
    for this to be done."
  - Non-goals.
  - Trade-offs split into advantages and disadvantages, both itemized,
    both honest.
  - Alternatives considered. Each named, each rejected with a reason.
  - Open questions. Real ones, with a lean.
  - Done-when: a concrete user takes a concrete action end-to-end.
  - Rollout in numbered phases, each with Goal, Allowed, Not allowed,
    Done-when.

  Does not belong in the spec:
  - File-by-file `lib/...` layout blocks. Belongs in the PR.
  - Ecto DDL with columns and indexes. Belongs in the migration.
  - Helm values, ClickHouse engines, Kubernetes CR YAML. Belongs in the
    chart PR.
  - Lifecycle pseudocode (`1. authorize then 2. insert then 3. enqueue`).
    Belongs in code.
  - Module paths and arities (`Tuist.Foo.bar/3`). Either go higher
    ("reuse the per-account billing primitive") or be ready to prove the
    named surface exists.

  Rule of thumb: if removing the line would not change the consumer's
  or operator's understanding of what they are getting, the line is
  implementation detail.

  ## Voice

  - Declarative, "we" voice. No hedging. State decisions as facts until
    marked future scope.
  - No em dashes. Use commas, colons, semicolons, or parentheses.
  - Tables for structured matrices (channel by resolution, environment
    by topology, command by filters). They compress better than
    bulleted prose.
  - Concrete examples make the contract real: a CLI invocation, a JSON
    payload, an agent transcript. Examples, not pseudocode.
  - Name decisions and give them reasons. "Two-line ceiling is
    deliberate, following Node.js experience that each additional line
    multiplies backport cost." Reviewers attach to named decisions.

  ## Section spine

  Lead with a Summary paragraph that names the problem, the mechanism,
  and the first consumer. Then choose from:

  1. Why (or Motivation): concrete pain.
  2. Current state: fact-stated.
  3. First use case or consumer: when there is one driving the design.
  4. Prior art: what peers do, what we take, what we discard.
  5. Proposal or Design: the surface as a contract. Sub-headed by
     capability (Endpoints, Schema, Auth, Telemetry).
  6. Scope: in and out, bulleted.
  7. Trade-offs: advantages and disadvantages, itemized.
  8. Alternatives considered: each named, each rejected with a reason.
  9. Rollout or Phases: numbered, each with the phase template below.
  10. Open questions: leaned, not dumped.
  11. Done when: behavioral.
  12. Future work: adjacent moves the design enables but does not commit
      to.
  13. References: links.

  Not every section is mandatory. Skip what does not add.

  ### Phase template

  Each phase carries:

  - Goal (one sentence).
  - Tasks (bulleted).
  - Allowed changes (keeps the diff in scope).
  - Not allowed (lets reviewers flag scope creep).
  - Deliverables.
  - Done when.

  Phases are independently reviewable and safely stoppable.

  ## What reviewers will push on

  Pre-empt these in the draft.

  1. Altitude. "This is implementation detail, move to the PR." Audit
     for DDL, layout blocks, pseudocode, function arities. Remove or
     paraphrase.
  2. Scope creep. Do not name build systems, providers, or features you
     are not adopting this year, unless explicitly taking inspiration.
     Cite as inspiration, not as scope.
  3. Lost framing. If a reviewer says "I'm a bit lost on the point" the
     remedy is rewriting the Why, not adding more detail. Frame as
     evolution of what exists unless it really is a rewrite.
  4. Reuse claims. Either go higher ("reuse the per-account billing
     primitive") or be precise enough to be checkable. Half-naming an
     API you might be wrong about is the worst spot.
  5. Edge cases and failure modes. What happens on retry, on a stuck
     job, on schema drift during the soak? Can validation be automated?
     Address inline; reviewers will ask.
  6. Security and threat model. When the design touches untrusted code,
     mounted credentials, cross-tenant flows, or public exposure: state
     the isolation posture per platform, scope mounts least-privilege
     and short-TTL, name the blast radius of token leakage, name SSRF
     and replay protections, name cross-account credential grants.
  7. Capacity and cost. When a design subtracts from a fixed pool, name
     the gating constraint and the fair-share story. When it adds an
     on-call surface, name the surface.
  8. Cross-surface consistency. REST, CLI, MCP, and dashboard should
     match. Items in Goals also appear in Design and in Done-when.
  9. Promotion. If something is viability-critical, it belongs in
     Goals, not Open Questions.
  10. Gating signal honesty. "1 week soak" with no RC adoption is "we
      waited a week." When a gate has no signal, say so, and name the
      signal you need.
  11. Naming. Action vocabularies should be small and generic
      (Stripe-style `resource.action`). Build-system or platform
      specifics belong under scoped subcommands when they have no peer
      (Xcode CAS has no Gradle equivalent).
  12. Backward compatibility. Default to additive surfaces. "Existing
      `tuist X show` and `tuist X list` remain unchanged." New
      capabilities are new subcommands and new tools, not changes to
      existing ones.
  13. Forward evolution. Can a future consumer with a different access
      pattern slot in without rewinding? Do not design that consumer
      here, but do not bake assumptions that block it.
  14. Audit attribution. When humans or agents act on shared resources,
      name the attribution path. Anonymous bot attribution is fine for
      v1 if explicitly chosen.

  ## Open questions: lean, do not dump

  An open question is "we genuinely do not know and want pushback," not
  "we have not thought about it." Each open question should:

  - Frame the trade-off.
  - State a lean if you have one.
  - Name the signal that would resolve it.

  Weak: "What should the cadence be?"
  Strong: "Cadence. Every 2 weeks felt right for parity with React
  Native. But the ceremony cost (RC cut, soak, promotion) may not be
  worth fortnightly for a 4-person team. Leaning toward 2 weeks with
  explicit permission to skip a cut when `main` is quiet. The signal
  that would change this: count of cuts skipped in the first quarter."

  ## Done-when

  Behavioral, not a checklist of components. A reader should be able to
  read it and know what to try in production.

  Weak: "Schema migration applied. Controllers added. Tests pass."
  Strong: "Under the `tuist` account, Hive can `POST /api/v1/sandboxes`
  with a Linux or macOS profile, poll until ready, exchange files via
  `PUT/GET /files/*`, expose an HTTP service via `POST /ports`, and
  `DELETE` to destroy. A `sandbox_sessions` row records the interval
  starting at `ready_at`, tagged with platform."

  ## Iteration

  Revisions are expected, and short.

  - When a reviewer convinces you: acknowledge and commit to the fix in
    a reply ("you're right, the wording is misleading, I'll rewrite
    that").
  - When a reviewer is wrong: defend the trade-off with rationale, close
    the loop, do not relitigate.
  - When the rewrite is up, a one-line "ready for another review" is
    normal.
  - A revision that halves the length and centers the open questions is
    usually the healthier shape than one that doubles the detail.
  """

  @doc """
  Returns the full spec writing guide as plain Markdown.

  Used by the `write_spec` MCP prompt and reusable by any internal agent
  that drafts specs.
  """
  def body, do: @body

  @doc """
  Builds the user-facing prompt body for drafting a spec.

  When `topic` is a non-empty string, the topic is woven into the lede
  so the model is primed before the guidelines load. Otherwise the
  guidelines are returned cold.
  """
  def write_spec_prompt(topic \\ nil)

  def write_spec_prompt(topic) when is_binary(topic) and topic != "" do
    """
    You are drafting a Hive spec about: #{topic}.

    Follow the house style below. Apply it before you start writing,
    not after. Hold the altitude rules in particular: a spec is a
    contract, not an implementation walkthrough.

    """ <> @body
  end

  def write_spec_prompt(_topic) do
    """
    You are about to draft a Hive spec. Follow the house style below.
    Apply it before you start writing, not after.

    """ <> @body
  end
end

---
name: hive-elixir-review
description: Project-specific PR-review rules for the tuist/hive Phoenix/Elixir codebase. Focuses on open-source secret hygiene, Noora data-part styling, OIDC auth, Helm deployment boundaries, release conventions, and a small set of Phoenix/Ecto/LiveView review rules that require diff awareness, semantic context, or cross-file reasoning that `mix format`/`mix credo` cannot do.
---

# Hive Elixir Review

This skill is intentionally narrow. Generic Elixir style, naming,
formatting, pipe chains, and lint hygiene are covered by `mix format`
and `mix credo` (including the custom checks under
`credo/checks/`). **Do not flag anything credo already catches** —
in particular: `Repo.*` calls inside `Enum.*` / `Stream.*` / `for`
(N+1 shape), or `timestamps/1` without an explicit `type:`. Focus on the
rules below because they need diff awareness, semantic context, or
cross-file reasoning that credo cannot do.

For each finding, cite `path:line` (or `Module.function/arity`) and
quote the relevant snippet.

Only report findings whose cited snippet is present in the PR diff. If
the concern comes from unchanged context, do not emit a finding, do not
mention it as a note, and do not create a "findings outside this PR's
diff" section. If every possible concern is outside the diff, return no
findings.

Do not infer violations from nearby lines. A finding must be anchored on
a changed line in the diff.

---

## 1. Open-source secret hygiene

Hive is an open-source repository. Production secrets live in the
`hive-k8s-production` 1Password vault and are referenced from source only
by name.

### Flag

- A real or plausible credential, token, OAuth secret, kubeconfig,
  database URL, Docker config JSON, service account token, `.env`
  contents, or private key added to source, tests, fixtures, docs,
  workflows, Helm values, or commit-oriented metadata. **Severity:
  critical.**
- Test fixtures or example env values that look real instead of obvious
  placeholders such as `"client-id"` or `"google-client-secret"`.
  **Severity: high.**
- Production `ExternalSecret` or Helm values that inline secret values
  instead of referencing remote 1Password item names and fields.
  **Severity: critical.**

### Do not flag

- Existing low-stakes secret reference names such as
  `hive-google-oauth/credential`, `hive-secret-key-base/password`, or the
  vault name `hive-k8s-production`.
- Phoenix development `secret_key_base` values in `config/dev.exs` or
  test-only placeholder secrets.

---

## 2. Styling with Noora and `data-part`

Hive styles server-rendered Phoenix HTML with Noora. The CSS convention
is one anchor selector per layout, component, or route, with internal
regions selected via `data-part`.

### Flag

- New CSS that introduces BEM-style child selectors such as
  `.headerbar__left`, `.layout__main`, or `.account-dropdown__menu`.
  Use nested `[data-part="..."]` selectors under the anchor instead.
  **Severity: medium.**
- New route-specific CSS that is not scoped under the route root id, for
  example `#login` or a future route id. **Severity: medium.**
- New component or layout CSS that reaches for utility or atomic classes
  instead of a component/layout anchor plus `data-part` regions.
  **Severity: medium.**
- A route template with a new root element that lacks a stable id while
  adding route-specific CSS. **Severity: medium.**
- Hardcoded spacing, surface, font, radius, or z-index values where an
  appropriate Noora variable exists. **Severity: low.**

### Do not flag

- Plain Noora component usage that does not need extra CSS.
- Pixel dimensions for assets or visual effects where Noora has no
  matching variable.
- The anchor class itself for reusable layouts or components, such as
  `.layout`, `.headerbar`, or `.account-dropdown`.

---

## 3. Auth and session boundaries

`HIVE_VISIBILITY=public|private` controls whether the dashboard is
gated. Public instances allow everyone through, while private instances
require a signed-in session. Login remains available in both modes.

### Flag

- A route that should be dashboard-protected but bypasses
  `HiveWeb.Plugs.RequireAuthenticated` or its existing router pipeline.
  **Severity: high.**
- A callback path that stores a user in the session before validating the
  provider's allowed-domain rules via `Hive.Auth.check_domain/2`.
  **Severity: high.**
- Provider logic that bypasses `Hive.Auth` and reads raw auth config
  directly from controllers or templates. **Severity: medium.**
- OIDC provider code that hardcodes discovered endpoints instead of
  relying on `ueberauth_oidcc` issuer discovery. **Severity: medium.**
- Google auth changes that remove the server-side domain check and rely
  only on the `hd` authorize hint. **Severity: high.**

### Do not flag

- Login being reachable when visibility is public. That is intentional
  so admins can sign in to a public instance.
- Compile-time Ueberauth provider declarations in `config/config.exs`.
  Runtime credentials are populated separately in `config/runtime.exs`.

---

## 4. Test setup boundaries

Tests run async-by-default and stub through Mimic, not `Application`
config. The static parts of this rule are enforced by credo; what's left
here is the cross-file and semantic piece.

### Flag

- A new mockable module used with Mimic (`stub/3`, `expect/3`) that is
  not added to `test/test_helper.exs` via `Mimic.copy/1`. The first
  stubbing test will silently no-op. **Severity: medium.**
- Tests for a new route or controller action that are not mirrored under
  the matching `test/hive_web/...` path. **Severity: low.**

### Do not flag

- Process-local Mimic stubs of modules already copied in
  `test/test_helper.exs`.
- Database setup done through the existing async-safe ConnCase/DataCase
  patterns.

---

## 5. Helm and production overlay boundaries

The Helm chart must remain generic by default. Tuist-specific production
values belong in `infra/helm/hive/values-production.yaml`.

### Flag

- Generic chart templates or `values.yaml` that hardcode
  `hive.tuist.dev`, `tuist.dev`-specific auth domains, the
  `hive-k8s-production` vault, Hetzner-specific storage classes, or
  production-only External Secrets settings. **Severity: high.**
- `values-production.yaml` changes that inline real secret values instead
  of 1Password remote references. **Severity: critical.**
- Deployment workflow changes that print kubeconfig contents, secret
  values, OAuth credentials, database URLs, or ExternalSecret payloads in
  logs. **Severity: critical.**
- Helm changes that drop the production smoke test, rollback behavior, or
  stuck-release recovery without replacing them with an equivalent safety
  mechanism. **Severity: medium.**

### Do not flag

- Tuist-specific values inside `infra/helm/hive/values-production.yaml`
  when they are references or non-secret deployment metadata.
- Generic chart support for External Secrets as long as values remain
  configurable and disabled unless the deployer opts in.

---

## 6. Releases and commit scopes

Hive has two release tracks: app releases from non-`helm` Conventional
Commit scopes and Helm chart releases from `helm`-scoped commits.

### Flag

- Release workflow changes that let Helm-only commits contribute to the
  app changelog, or non-Helm commits contribute to the Helm changelog.
  **Severity: medium.**
- Changes that remove the `server@X.Y.Z` or `helm@X.Y.Z` tag prefixes
  from release detection or tagging. **Severity: high.**
- PR titles or commit-message guidance that omits explicit Conventional
  Commit scopes when documenting examples for this repo. **Severity:
  low.**

### Do not flag

- Existing `git-cliff` behavior that accepts unscoped commits. The repo
  convention still prefers explicit scopes, but release parsing tolerates
  them.

---

## 7. LiveView lifecycle

The forage, dashboard, meadow, and spec sections use Phoenix LiveView.
These rules catch lifecycle bugs that need semantic context (which
routes are tenant-scoped, what counts as "slow", which collections grow)
and so live outside credo.

### Flag

- A new LiveView route on a tenant-scoped resource whose `mount/3` does
  not gate access via the corresponding LetMe policy (e.g.
  `Hive.Forage.Policy`). **Severity: high.**
- A `mount/3` performing a fetch that can exceed ~100ms (DB query,
  agent run, external HTTP) without `Phoenix.LiveView.assign_async/3`.
  **Severity: medium.**
- A new LiveView that assigns an unbounded collection
  (e.g. `assign(socket, :specs, list)`) instead of
  `Phoenix.LiveView.stream/3`. **Severity: medium.**
- A `handle_event/3` performing a slow operation (DB write, agent run,
  external HTTP) inline instead of offloading to a Task or background
  process. **Severity: medium.**
- New domain logic (data access, multi-step flows, business rules)
  placed inside a controller, LiveView `mount/3`/`handle_event/3`, or
  HEEx template instead of a context module under `lib/hive/<domain>/`.
  The web layer should orchestrate; the domain should compute.
  **Severity: medium.**

### Do not flag

- Existing controller-rendered HEEx templates where the page does not
  need LiveView interactivity.
- LiveViews that legitimately need synchronous data at mount (page
  title, OpenGraph metadata) when the fetch is bounded and fast.
- Thin presentation helpers defined in the LiveView module itself
  (formatting, derived assigns) that don't reach for the DB or external
  systems.

---

## 8. Ecto changesets, tenancy, and templates

These rules require diff awareness or cross-file tracing that credo
cannot do.

### Flag

- A new or materially changed `*_changeset/N` function in `lib/hive/**`
  whose diff does not also add or update a test calling that function in
  the matching `test/hive/**/*_test.exs`. Material changes include any
  new/modified `cast`, `validate_*`, `unique_constraint`,
  `foreign_key_constraint`, or `put_change` line. **Severity: medium.**
- A changeset that `cast`s a programmatic foreign-key field (`user_id`,
  `account_id`, `organization_id`, `actor_id`, or any FK naming the
  actor/owner) from user params instead of setting it via `put_change`
  from a verified actor. **Severity: high.**
- A controller, LiveView, or context function calling
  `Hive.Repo.get(Schema, id)` / `Repo.one(from s in Schema, where: s.id == ^id)`
  for a tenant-owned schema without a tenant constraint, when the call
  site already has the tenant in scope. **Severity: high.**
- A HEEx template accessing `@record.assoc.field` with no upstream
  evidence (trace through the context function) that the association was
  preloaded. The render-time crash on `%Ecto.Association.NotLoaded{}` is
  silent at compile time. **Severity: medium.**

### Do not flag

- Trivial mechanical changeset edits (renaming a field already covered
  by an existing test, formatting-only churn, reordering pipe steps).
- Diffs that exercise the changeset indirectly through a higher-level
  context test that still passes.

---

## 9. Documentation and operator-facing surfaces

`README.md` describes behavior, configuration, and outcomes for the
operator or end user of any Hive deployment. Tuist-specific operational
details (production cluster, 1Password vault names, ESO config, Hetzner
storage classes, deployment workflow internals) belong in `AGENTS.md`,
not the README. Implementation details — module names, struct fields,
private helpers, refactoring artifacts — belong in code or `AGENTS.md`,
never in user-facing docs.

### Flag

- A PR that adds, changes, or removes a feature visible to operators or
  end users (new env var, new route, new ingestion source, changed
  default, removed capability) without updating `README.md` in the same
  diff. **Severity: medium.**
- A `README.md` change that introduces Tuist-specific operational
  details (vault names, cluster names, ESO config, hcloud storage
  classes, production-only workflow notes) instead of putting them in
  `AGENTS.md`. **Severity: low.**
- A `README.md` change that leaks implementation details (module names,
  function signatures, private struct fields, internal refactoring
  notes) instead of describing observable behavior. **Severity: low.**
- A doc cross-reference to something that no longer exists or now works
  differently after the diff (stale env var, removed route, renamed
  flag). **Severity: medium.**

### Do not flag

- Internal-only changes (refactors, perf, ops-only paths, tests,
  fixtures) that have no operator- or user-visible effect.
- Existing implementation references in `AGENTS.md` — that file is
  explicitly the place for them.
- README additions for genuinely user-facing operational concerns
  (allowed-domain configuration, visibility modes) even if Tuist also
  uses them.

---

## Before submitting findings

For each finding, confirm:

1. The `path:line` is real and the snippet appears in the diff.
2. The category above is one of 1–9; if it isn't, downgrade to a
   question (`uncertain: ...`) rather than asserting a finding.
3. The severity is set: **critical** (auth bypass / cross-tenant read or
   write / secret leak), **high** (likely security or correctness bug),
   **medium** (compliance / consistency gap), **low** (nice-to-have).
4. You are not reporting an unchanged line as a finding. Unchanged
   context can explain a diff finding, but cannot be the finding itself.

---

## Out of scope (handled elsewhere — do not flag)

- Module/function naming, pipe-chain start, nesting depth, parentheses
  on no-arg calls → `mix format` and built-in credo checks.
- Migration `timestamps(...)` or schema `timestamps(...)` without
  explicit `type:` → `Hive.Credo.Checks.TimestampsType`.
- `Repo.*` calls inside `Enum.*` / `Stream.*` / `for` (N+1 shape) →
  `Hive.Credo.Checks.RepoCallInEnum`.
- Missing `@spec` / `@type` — this codebase intentionally avoids
  typespecs. Never suggest adding them.
- Missing `@doc` / `@moduledoc` on internal helper modules.
- `String.to_atom/1` on user input → credo's `UnsafeToAtom`.

---

## Skill maintenance (not a review-time instruction)

A rule belongs in this skill **only** when it needs at least one of:

- **The PR diff** ("changed in this PR", "co-changed with X").
- **Semantic context** that depends on the project ("this schema is
  tenant-owned", "this route is public", "this is a request path").
- **Cross-file or cross-module reasoning** ("was this association
  preloaded upstream", "is the mock registered in `test_helper.exs`").
- **Human-shaped pattern recognition** ("this string looks like a real
  credential", "this leaks implementation details").
- **External-system awareness** that the code itself doesn't expose
  (Helm overlays, 1Password references, deployment workflow).

A rule that reduces to "match this AST shape in files under this path"
belongs in `credo/checks/`, not here. When the temptation is to add a
new section to this skill, first ask: could a Credo check do it? If
yes, write the check instead and leave only the semantic escalation
(severity by context, hot-path judgment) for the skill.

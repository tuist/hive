# Hive

Phoenix application that hosts Tuist's agentic domain orchestration. MPL-2.0 licensed; runs as a single deployment per organization (Tuist hosts its own at `hive.tuist.dev`; the chart in `infra/helm/hive` supports self-hosting).

**This is an open-source repository.** Treat every commit and PR as world-readable. Never paste credentials, tokens, kubeconfigs, OAuth secrets, database URLs, or `.env` contents into source, tests, fixtures, commit messages, or PR bodies. Production secrets live exclusively in the `hive-k8s-production` 1Password vault and are pulled into Kubernetes via External Secrets at deploy time — the repo only references them by name (`hive-google-oauth/credential`), never by value. Reference names are not secrets but treat them as low-stakes signal: assume an attacker reading the repo learns them. Test fixtures and example env values must use obvious placeholders (e.g. `"client-id"`, `"google-client-secret"`), never real credentials even if revoked.

## Tech Stack

- **Backend**: Elixir 1.20.1 on Erlang/OTP 29.0.2, Phoenix 1.8
- **HTTP**: Bandit
- **Database**: PostgreSQL via Ecto
- **Frontend**: Phoenix HTML + Noora design system; esbuild bundles `assets/`
- **LiveView** powers the forage section (`lib/hive_web/live/`); login is still server-rendered HTML from a controller
- **Agentic workflows** built on [Condukt](https://github.com/tuist/condukt) (Elixir agent framework wrapping ReqLLM); shared call site is `Hive.Agents.Sessions`
- **Tool versions** pinned in `mise.toml`

## Layout

- `lib/hive/` — domain modules (currently just `auth.ex`, `repo.ex`, `application.ex`, `release.ex`)
- `lib/hive/agents/` — agent infrastructure: `Hive.Agents` (LLM config), `Hive.Agents.Sessions` (Condukt entry point), `Hive.Agents.StyleGuide` (shared prose rules). Individual agents live under `lib/hive/<domain>/agents/<name>_agent.ex`.
- `lib/hive_web/` — web layer
  - `components/layouts.ex` — `Layouts.app` (controller HTML shell) + `Layouts.root` (LiveView root layout) + `Layouts.dashboard` (header + sidebar + content slot)
  - `live/forage_live/` — LiveViews for the forage section; `components/forage_components.ex` holds their presentational markup; authorization is a LetMe policy (`lib/hive/forage/policy.ex`)
  - `controllers/page_html.ex` — login page (raw HEEx, controller-rendered)
  - `auth_controller.ex` — unified OIDC flow at `/auth/:provider` (start + callback)
  - `plugs/require_authenticated.ex` — gates routes when `Auth.enabled?()`
- `assets/css/app.css` — imports Noora's CSS; Hive-specific styling layered on top
- `config/` — Phoenix config; `runtime.exs` reads env vars into the `:hive, :auth` keyword list
- `priv/static/images/logo.png` — used as headerbar, login frame, favicon, and README image
- `infra/helm/hive/` — generic Helm chart with `values-production.yaml` Tuist overlay
- `.github/workflows/deploy.yml` — builds, pushes to GHCR, `helm upgrade` against the production cluster

## Setup

```bash
mise install
mix deps.get
mix ecto.setup
mix phx.server
```

Dev port is allocated dynamically via `Hive.Config.DevInstance` (see `config/dev_instance.exs`) — multiple worktrees coexist without colliding. Look at `lsof -i:<port>` or read the dev instance file to find the actual port.

## Common Commands

- `mix test` — full suite (clean DB each run; no shared env mutation)
- `mix test test/path/to/file.exs:LINE` — single test
- `mix compile --warnings-as-errors` — strict compile
- `mix format` — formatter
- `mix credo` — lint
- `helm template hive infra/helm/hive` — render generic chart
- `helm template hive infra/helm/hive -f infra/helm/hive/values-production.yaml` — render Tuist's production manifest

## Auth

`HIVE_VISIBILITY=public|private` (default `public`) controls whether `HiveWeb.Plugs.RequireAuthenticated` gates the dashboard. Public lets everyone through. Private requires a session; missing session redirects to `/login`. Login is always available so admins can sign in to a public instance.

Auth itself is delegated to [Ueberauth] + [ueberauth_oidcc] (an OIDC strategy built on the `oidcc` library, which auto-discovers each provider's endpoints from `.well-known/openid-configuration`). `config/runtime.exs` reads env vars and registers issuers + strategies; `Hive.Auth` exposes only what the app's UI and callback need (`visibility/0`, `private?/0`, `public?/0`, `providers/0`, `check_domain/2`, `current_user/1`).

[Ueberauth]: https://github.com/ueberauth/ueberauth
[ueberauth_oidcc]: https://github.com/erlef/ueberauth_oidcc

Two providers are supported and can run side-by-side:

- **Google**: preset on `https://accounts.google.com`; needs `HIVE_GOOGLE_CLIENT_ID/_SECRET`. `HIVE_GOOGLE_ALLOWED_DOMAINS` with a single domain also pushes Google's `hd=` hint to the authorize redirect.
- **Generic OIDC**: point `HIVE_OIDC_ISSUER` at any issuer URL with a `.well-known/openid-configuration`; supply `HIVE_OIDC_CLIENT_ID/_SECRET` (and optionally `HIVE_OIDC_DISPLAY_NAME`).

Routes: Ueberauth's plug owns `/auth/:provider` (redirect to IdP) and `/auth/:provider/callback` (token exchange + userinfo). The Hive `AuthController.callback/2` action reads `conn.assigns.ueberauth_auth`, runs `Hive.Auth.check_domain/2` against the provider's allowlist, and stores the user in the session.

## Authorization

Hive uses [LetMe] as its authorization framework. A LetMe `Policy` declares the actions allowed on an object and the named checks each action needs; the checks themselves are plain boolean functions over `{subject, object}` and live in a sibling `Checks` module.

[LetMe]: https://hexdocs.pm/let_me

Layout convention: `lib/hive/<domain>/policy.ex` declares `use LetMe.Policy` and the rule tree; `lib/hive/<domain>/policy/checks.ex` exposes the boolean checks referenced by name. Call sites use `Policy.authorize?(:object_action, subject, object)`.

The persisted authorization role lives on `Hive.Accounts.User.role` and is the single source of truth for authorization. It is an ordinal enum, weakest to strongest: `:collaborator` (signed in, outside the org), `:member` (part of the org), `:admin` (explicitly promoted; gates surfaces like the audit trail). The role is derived from the email domain at signup (matching `HIVE_ORG_DOMAINS` → `:member`, otherwise `:collaborator`; everyone defaults to `:member` when no org domains are set) and then stored, so changing `HIVE_ORG_DOMAINS` later does not reclassify existing users. `Hive.Auth.role/1` returns this stored value (with `:anonymous` for `nil`); `member?/1` is true for `:member` and `:admin`, `admin?/1` only for `:admin`.

Examples to follow:

- `lib/hive/forage/policy.ex` + `lib/hive/forage/policy/checks.ex` — public vs org-member access to forage sources.
- `lib/hive/audit/policy.ex` + `lib/hive/audit/policy/checks.ex` — admin-only access to the audit trail.

## Audit

`Hive.Audit` records a single append-only trail of user, agent, webhook, and worker actions. Each entry captures who did something (the actor: id, email, name, role), where the action came from (the interface: `dashboard | mcp | webhook | worker | system`), what was acted on (target type/id/label, with metadata), and when it occurred. Entries surface through `HiveWeb.AuditLive` at `/audit` (gated by `Hive.Audit.Policy` on the stored `:admin` role) and through the `list_audit_activities` / `get_audit_activity` MCP tools.

The actor and interface for the current process are stored in the process dictionary so call sites that record events don't need to thread them through every function. Set them at the request boundary (`Audit.put_context/1` is already called from `HiveWeb.Plugs.RequireAuthenticated`, `HiveWeb.Plugs.MCPAuthentication`, and `HiveWeb.DashboardLive.Hooks`) and call `Audit.record(action, attrs)` from wherever the event happens. Workers, webhook handlers, and one-off scripts should call `put_context/1` themselves with the right interface before recording.

When in doubt about action names, follow the dotted `domain.verb` convention: `user.signed_in`, `spec.created`, `domain.webhook_received`, `forage.feature_request.created`. `target_type` is a short noun (`user`, `spec`, `domain`, `feature_request`, `github_issue`, `grafana_alert`); `Hive.Audit.resource_path/3` knows how to turn a `target_type`+`target_id` into a link for the UI.

## Slack link unfurling

Slack's `link_shared` event is handled in `Hive.Slack.Events` and dispatched to `Hive.Slack.Workers.UnfurlLinks`, which walks each Uniform Resource Locator ([URL](https://developer.mozilla.org/en-US/docs/Learn/Common_questions/Web_mechanics/What_is_a_URL)) through `Hive.Slack.Unfurler` and posts the resulting previews back via `chat.unfurl`. Only hosts that match `HiveWeb.Endpoint.url()` are considered.

`Hive.Slack.Unfurler` resolves the dashboard route with `Phoenix.Router.route_info/4` and asks the owning LiveView or controller to build the preview. Keep link-to-block mapping close to that route. Do not add a central list of path patterns or domain-specific unfurl modules.

Every dashboard page should support Slack unfurling with [Block Kit](https://docs.slack.dev/block-kit/) blocks:

1. For static pages, expose `open_graph/0`; `Hive.Slack.Unfurler` converts it to a Block Kit payload.
2. For dynamic pages, implement `slack_unfurl(uri, params)` in the owning route module with `@behaviour Hive.Slack.Unfurl`. Fetch the resource with an anonymous viewer when including resource data, return `Hive.Slack.Unfurl.BlockKit.open_graph/2` or `Hive.Slack.Unfurl.BlockKit.generic/2`, and return `:skip` when the resource is missing or private.
3. For admin-only or account-specific pages, use generic page metadata unless the concrete resource is safe for anonymous visitors.
4. Add route-dispatch coverage in `test/hive/slack/unfurler_test.exs` or a narrower route test when the page needs bespoke behavior. Cover the happy path, private/anonymous skip, and not-found cases for resource pages.

Visibility for unfurls follows the dashboard's anonymous view: a Slack workspace member is treated as an external visitor, so any resource that requires a Hive session stays opaque.

## Agents

Agentic workflows are built on [Condukt], an Elixir agent framework that wraps [ReqLLM]. Most model-backed features share the profile marked **Use for Hive inference** under **Ops -> Inference -> Profiles**. Coding runs can instead use the profile marked **Use for Hive coding**, with the general inference profile as their fallback. Hive uses an encrypted Hive-owned token to call its own `/inference/v1` gateway and records usage on the selected profile. If no applicable profile is marked, Hive falls back to three launch-time environment variables:

[Condukt]: https://github.com/tuist/condukt
[ReqLLM]: https://hexdocs.pm/req_llm

- `HIVE_LLM_API_KEY` — provider API key (Anthropic, OpenAI, Fireworks, etc.)
- `HIVE_LLM_MODEL` — `provider:model_id` (e.g. `anthropic:claude-haiku-4-5`, `openai:gpt-4o-mini`)
- `HIVE_LLM_BASE_URL` — optional endpoint override

When no Hive inference profile is marked and `HIVE_LLM_API_KEY` is unset, `Hive.Agents.enabled?/0` returns `false`, `Hive.Agents.Sessions.run/3` returns `{:error, :llm_not_configured}`, and agentic features stay dormant. The rest of Hive keeps booting, so deploying without an LLM is supported.

Treat language-model tokens as a metered production resource. Any agentic workflow that runs from scheduled jobs, workers, webhooks, or syncers must be idempotent, persist durable evaluation state for generated, ignored, or no-op outcomes, cap prompt and fetched-context sizes, and avoid re-evaluating unchanged records. Hard provider failures such as credit limits, invalid credentials, and suspended accounts should become non-retryable job results instead of repeated attempts. Add regression coverage that proves repeated runs over the same input do not spend again.

### Adding an agent

1. Create `lib/hive/<domain>/agents/<name>_agent.ex` (e.g. `lib/hive/forage/agents/issue_triage_agent.ex`).
2. `use Condukt` and implement `system_prompt/0` and `tools/0`. Append `Hive.Agents.StyleGuide.prose_rules()` to the system prompt so the cross-cutting style rules apply.
3. Expose a public entry point (e.g. `triage(issue)`) that calls `Hive.Agents.Sessions.run/3`. Don't call `Condukt.run/3` directly: the wrapper merges the resolved LLM client options and is the hook point for future audit-trail wiring.
4. Define tools inline with `Condukt.tool(name:, description:, parameters:, call:)`. Keep their `call:` callbacks short and delegate to a context module under `lib/hive/<domain>/`.
5. In tests, `Mimic.copy/1` the agent module in `test/test_helper.exs` and stub the entry-point function. `Mimic.copy(Condukt, type_check: true)` is already in place for end-to-end stubs. For unit tests of code that doesn't need a real LLM round-trip, `Hive.TestSupport.Agents.NoopAgent` is a minimal `use Condukt` agent backed by a runtime that returns `{:ok, "handled: " <> prompt}`.

## Releases

Versioning is driven by [git-cliff] and Conventional Commits, modeled after the [tuist/tuist] monorepo. Two independent release tracks live in this repo:

[git-cliff]: https://git-cliff.org
[tuist/tuist]: https://github.com/tuist/tuist/blob/main/.github/workflows/release.yml

- **App** (Docker image `ghcr.io/tuist/hive`) — versioned via plain semver `X.Y.Z` tags. Config: `cliff.toml` at the repo root. Any Conventional Commit that isn't `(helm)`-scoped contributes (so `feat(auth):`, `fix:`, `refactor(css):` etc. all count). The release workflow still recognizes the legacy `server@X.Y.Z` tags for bump detection until the latest tag is a plain one.
- **Helm chart** (OCI artifact at `oci://ghcr.io/tuist/charts/hive`) — versioned via `helm@X.Y.Z` tags. Config: `infra/helm/hive/cliff.toml`. Only `(helm)`-scoped commits count.

`.github/workflows/release.yml` runs on every push to `main`:

1. **check-releases** uses `git cliff --bumped-version` to figure out whether either component has releasable changes since the last app tag (plain `X.Y.Z`, or the legacy `server@X.Y.Z`) / `helm@*` tag.
2. **release-server** (conditional): generates release notes, refreshes `CHANGELOG.md`, builds and pushes the Docker image tagged with the new version (and `:latest`).
3. **release-helm** (conditional): generates release notes, bumps `Chart.yaml` (`version` + `appVersion`), refreshes `infra/helm/hive/CHANGELOG.md`, runs `helm package` + `helm push` to the GHCR OCI registry.
4. **commit-and-release**: creates git tags, publishes a GitHub Release per component with the cliff-generated notes, then commits the `CHANGELOG.md` / `Chart.yaml` bumps back to `main` with `[skip ci]`.

The existing **`deploy.yml`** still fires on every push and ships a sha-tagged image to production immediately — this is the canonical promotion path. The release workflow runs in parallel and produces versioned artifacts for anyone consuming the Docker image or Helm chart out-of-band.

To preview what the next release notes will look like locally:

```bash
mise exec -- git-cliff --config cliff.toml                       # app
mise exec -- git-cliff --include-path "infra/helm/**/*" \
  --config infra/helm/hive/cliff.toml                            # helm chart
```

## Tuist's production deployment

`infra/helm/hive/values-production.yaml` is the overlay Tuist applies to the chart at deploy time via `.github/workflows/deploy.yml`. The production cluster assumes cert-manager, ingress-nginx, external-dns, the CloudNativePG operator, the External Secrets Operator with a `ClusterSecretStore` named `onepassword-hive` pointing at the `hive-k8s-production` 1Password vault, Hetzner Cloud block storage (`hcloud-volumes`), and dedicated Agent Sandbox workers with the `gvisor` RuntimeClass.

**Coding runs are currently disabled in production** (`codingRuns.provider: disabled` in `values-production.yaml`). The `coding-sandbox` pool is a single fixed `cpx42` node that fits roughly four concurrent sandboxes, with no autoscaler watching the `hive-production` cluster, and the gVisor preflight gate was blocking every deploy. The deploy workflow keys its Agent Sandbox install and gVisor verification off that value, so flipping the provider back to `kubernetes` restores the preflight gates automatically with no second flag to keep in sync. Making capacity elastic needs two changes in `tuist/tuist`: `cluster-autoscaler-node-group-{min,max}-size` annotations on the `coding-sandbox` machineDeployment in `cluster-hive-production.yaml` (mirroring `md-processor` in `cluster-production.yaml`), and a `cluster-autoscaler-hive-production` instance in `infra/k8s/mgmt/` alongside the existing per-workload-cluster autoscalers. Until then, raising Hive's Oban `:agents` concurrency or the sandbox resource quota past one node's capacity converts queueing into unschedulable-pod failures.

When enabled, coding runs are scheduled only on Hetzner workers labeled and tainted with `hive.tuist.dev/workload=coding-sandbox`. The shared Cluster API template installs gVisor and configures the `runsc` containerd handler on that pool. The deploy workflow installs the pinned Kubernetes Agent Sandbox controller and refuses to deploy the production overlay unless a real gVisor preflight pod succeeds on matching worker capacity. Sandbox pods run in the `hive-sandboxes` namespace with restricted Pod Security admission, no mounted service-account token, namespace-scoped permissions, public-web-only egress, and a four-pod resource quota.

The `hive-production` Cluster API declaration lives in `tuist/tuist` at `infra/k8s/clusters/cluster-hive-production.yaml`, next to the shared `tuist-hcloud` ClusterClass. The management-cluster apply workflow owns reconciliation of both the dedicated worker pool and its gVisor bootstrap.

The 1Password vault must contain `kubeconfig: hive-production` (used by GitHub Actions), `hive-secret-key-base/password` (generated with `mix phx.gen.secret`), `hive-google-oauth/username` + `hive-google-oauth/credential` (Google OAuth client ID + secret, wired into `HIVE_GOOGLE_CLIENT_ID/_SECRET`), `hive-slack-oauth/username` + `hive-slack-oauth/credential` + `hive-slack-signing-secret/credential` + `hive-slack-allowed-team-ids/credential` (Slack app client ID, client secret, signing secret, and allowed workspace IDs), `hive-mailgun-smtp/username` + `hive-mailgun-smtp/credential` (Mailgun sending username and password), `hive-sentry/dsn` (Sentry [Data Source Name](https://docs.sentry.io/product/sentry-basics/dsn-explainer/)), `hive-ghcr-pull/notesPlain` (base64 Docker config JSON for GHCR), and `hive-postgres-backup/username` + `hive-postgres-backup/credential` (CNPG backup creds).

Bootstrap script for the `ClusterSecretStore` (run once when standing up the cluster):

```bash
kubectl create namespace onepassword --dry-run=client -o yaml | kubectl apply -f -
kubectl -n onepassword create secret generic onepassword-hive-sa-token \
  --from-literal=token="$(op read 'op://Founders/Service Account Auth Token: hive-k8s-production-sa/credential')" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'YAML' | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword-hive
spec:
  provider:
    onepasswordSDK:
      vault: hive-k8s-production
      auth:
        serviceAccountSecretRef:
          name: onepassword-hive-sa-token
          namespace: onepassword
          key: token
YAML
```

## Conventions

- **PR titles and commit messages use Conventional Commits with an explicit scope naming the domain.** Examples: `feat(auth): support Apple sign-in`, `refactor(helm): genericize the chart`, `style(web): adopt tuist-style login`, `test(auth): use Mimic instead of put_env`, `ci(release): pin action SHAs`, `docs(deploy): document Tuist's overlay`. The scope drives `git-cliff`'s changelog grouping: `(helm)` commits feed the chart's release notes; every other scope feeds the app's. Don't omit the scope (`feat:` alone is acceptable in cliff but undermines reviewer/release-note clarity).
- **Workarounds are not acceptable solutions.** Fix the underlying contract, dependency boundary, or product behavior. If a temporary mitigation is unavoidable, call it out explicitly with the owner, removal condition, and follow-up issue before merging.
- **`README.md` is only the repository overview.** When you add, change, or remove a feature visible to operators or end users (new environment variable, new route, new ingestion source, changed default, removed capability), update the docs instead of `README.md` so public documentation reflects reality. Operational details that are Tuist-specific (production cluster, 1Password vaults, etc.) belong in `AGENTS.md`, not the public docs.
- **Keep documentation current and user-facing; do not leak implementation details.** Documentation should describe behavior, configuration, and outcomes from the operator's or end user's perspective, not internal module names, function signatures, code paths, or refactoring artifacts. If a change ships, the docs that describe it ship in the same PR; if a doc references something that no longer exists or now works differently, update it instead of leaving it stale. Module names, struct fields, private helpers, and other internals belong in code and `AGENTS.md`, not in `README.md` or other user-facing surfaces.
- **Keep the authorization guide in sync with product permissions.** When changing roles, policies, plugs, route visibility, or dashboard/Model Context Protocol ([MCP](https://modelcontextprotocol.io/)) access rules, update `docs/guide/self-hosting/authorization.md`, especially the "What each role can do" table, so the public role matrix stays true.
- **Keep the model gateway guide current.** Whenever you add, change, or remove an agentic workflow or model-gateway capability, update `docs/guide/self-hosting/inference.md`, especially the "Agentic Workflows" section, so operators know what becomes active when large language model configuration is present.
- **Keep dashboard and MCP surfaces in parity.** When adding, changing, or removing dashboard actions for user-visible resources such as specs, comments, forage items, domains, or audit records, check whether MCP clients need the same capability. Add or update the corresponding MCP tool and its one-file-per-tool test, or leave an explicit note in the PR explaining why the dashboard-only behavior is intentional.
- Prefer editing existing files over creating new ones; keep modules small and domain-focused.
- No comments unless the *why* is non-obvious. Don't restate what well-named code does.
- For UI work, the reference design system is Noora (already in `deps/`). Reference layouts and patterns from `../tuist/server` and `../atlas` when in doubt.
- Before adding or restyling any table or list surface, inspect the closest equivalent in `../tuist/server` and mirror its Noora table components, row density, header/action layout, badges, empty/loading states, and pagination behavior. Those pages are the designer-reviewed reference; Hive should only diverge when there is a product-specific reason called out in the pull request.
- Use Noora dropdown/select components for user-facing dropdowns instead of native browser `<select>` controls.
- Every list-style table should ship with three controls: filter chips, a free-text search box, and pagination. Use Noora's `filter_dropdown` + `active_filter` for the filter UI, a Noora `text_input` of `type="search"` for the search, and the prev/next chevron pattern from `../tuist/server` (`RunnerWorkflowsLive`, mirrored in `lib/hive_web/live/audit_live.ex`) for pagination. Render pagination centered below the table, without a separator bar. The only reason to skip any of the three is a bounded, fixed-size dataset.
- Do not add Back buttons to pages. The browser already provides back navigation; prefer clear page hierarchy and contextual links only when they go to a specific destination other than browser history.
- Every user-facing HTML page should include OpenGraph metadata with an image. Define the page-specific OpenGraph data in the controller or LiveView that owns the page, pass it through `OpenGraph.assigns/1` for LiveViews, or pass `open_graph:` into `Layouts.app` for controller-rendered pages.
- **Every list-style surface ships both an Atom 1.0 feed at `<path>/atom.xml` and an RSS 2.0 feed at `<path>/rss.xml` so people can subscribe through any reader.** Add a pair of `FeedController` actions (`<name>_atom`, `<name>_rss`) that share a single feed-builder helper and reuse the same context module as the HTML page (visibility is enforced the same way: anonymous requests only see public items). Wire both routes under the `:feed` pipeline in `router.ex`. On the matching LiveView/controller, assign `:atom_feed` (`%{title: ..., atom_href: ..., rss_href: ...}`) so the root layout renders the `<link rel="alternate" type="application/atom+xml">` + `application/rss+xml` discovery tags, and render `<Layouts.feeds_dropdown id="..." atom_href={...} rss_href={...} />` to the right of the page title-group (inside `data-part="header-actions"`) so visitors can grab the URL from the page itself. Existing feeds: forage feature requests, GitHub issues, Grafana alerts, specs, and per-domain feeds at `/domains/:id/atom.xml` (which merge the GitHub issues + Grafana alerts that belong to a single domain).
- Tests live under `test/hive_web/...` mirroring `lib/hive_web/...` paths.
- Every MCP tool module (`lib/hive/mcp/components/tools/<name>.ex`) has its own test module at `test/hive/mcp/components/tools/<name>_test.exs`. Don't bundle multiple tool tests into one file even when they share setup helpers; one file per tool keeps the layout discoverable and lets failures point at a specific tool.
- **All tests are `async: true`.** Never mutate `Application` config in `setup`/`on_exit`: that serializes the suite. When a test needs to control behavior that reads from app config, stub the wrapping module with [Mimic](https://github.com/edgurgel/mimic) (process-local; safe under parallel execution). `test/test_helper.exs` lists which modules are Mimic-copied; add yours there when introducing new mockable surfaces.

### CSS

The stylesheet is split by responsibility, not bundled into one file:

```
assets/css/
├── app.css                # @imports + base resets only
├── layouts/<name>.css     # chrome shared across many routes (.layout, .headerbar, …)
├── components/<name>.css  # extensions/combinations of Noora components (.account-dropdown, …)
└── routes/<name>.css      # everything specific to one route, scoped under #<route-id>
```

**Anchor + `data-part` (no BEM, no utilities).** Every layout/component/route has **one anchor selector** — a class for components and layouts (`.headerbar`, `.layout`, `.account-dropdown`) or an `#id` for routes (`#login`) — and **all internal regions are addressed via `data-part="name"`** on the HTML element, with the CSS nested under the anchor:

```css
.headerbar {
  & [data-part="left-section"] { ... }
  & [data-part="right-section"] { ... }
  & [data-part="title"] { ... }
}
```

Do **not** write BEM-style child classes (`.headerbar__left`, `.layout__main`, `.layout__content`), and do **not** reach for utility/atomic classes. This is the convention `../tuist/server` and `../atlas` use; it keeps HTML free of class soup and styles co-located with the anchor they extend. When in doubt, grep one of those repos for the closest equivalent.

**Other rules:**

- **Routes** get an `id` on their root element (`<main id="login">`, future `<div id="overview">`). All route-specific CSS lives nested under `#<route-id>` in `routes/<route>.css`.
- **Components in `components/`** are reusable widgets that extend a Noora component or compose several (e.g. `.account-dropdown` wraps `<.avatar>`). Plain Noora usage doesn't need a file here.
- **Use Noora variables** (`--noora-spacing-*`, `--noora-surface-*`, `--noora-font-*`, `--noora-radius-*`, `--noora-z-index-*`) over hardcoded values. Pixel dimensions for non-Noora-sized things (logo, gradient blobs) are fine when no variable fits.
- **Nest** with native CSS (`&` operator). Media queries nest inside the anchor too.

## Deployment

`main` auto-deploys via `.github/workflows/deploy.yml`: builds + pushes `ghcr.io/tuist/hive`, then `helm upgrade --install` against the `hive-production` cluster with the production overlay. Secrets come from 1Password (vault `hive-k8s-production`) via External Secrets Operator.

The chart is generic by default — Tuist-specific values (host, allowed domains, ESO config, hcloud storage, 1Password remote refs) live in `infra/helm/hive/values-production.yaml`. Anyone deploying their own Hive doesn't load that file.

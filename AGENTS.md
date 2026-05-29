# Hive

Phoenix application that hosts Tuist's agentic product orchestration. MPL-2.0 licensed; runs as a single deployment per organization (Tuist hosts its own at `hive.tuist.dev`; the chart in `infra/helm/hive` supports self-hosting).

## Tech Stack

- **Backend**: Elixir 1.19.5 on Erlang/OTP 29.0, Phoenix 1.8
- **HTTP**: Bandit
- **Database**: PostgreSQL via Ecto
- **Frontend**: Phoenix HTML + Noora design system; esbuild bundles `assets/`
- **No LiveView yet** — pages are server-rendered HTML from controllers
- **Tool versions** pinned in `mise.toml`

## Layout

- `lib/hive/` — domain modules (currently just `auth.ex`, `repo.ex`, `application.ex`, `release.ex`)
- `lib/hive_web/` — web layer
  - `components/layouts.ex` — `Layouts.app` (HTML shell) + `Layouts.dashboard` (header + sidebar + content slot)
  - `controllers/page_html.ex` — login + dashboard pages (raw HEEx, no LiveView)
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

Auth is configured under `:hive, :auth` (see `config/runtime.exs`). Hive runs at most one OIDC provider per instance, selected via `HIVE_OIDC_PROVIDER=google|generic`. `Hive.Auth.provider/0` returns the configured provider map (or `nil`). The controller flow at `/auth/:provider` is provider-agnostic; `:provider` matches the configured provider's key (`"google"` or `"oidc"`).

When `HIVE_OIDC_PROVIDER=google`, Hive injects Google's hardcoded authorize/token/userinfo URLs and, with a single-entry `HIVE_OIDC_ALLOWED_DOMAINS`, adds the `hd=` hint to the authorize redirect. The allowed-domains list is enforced on callback regardless of the `hd=` hint.

## Conventions

- Conventional Commits for PR titles and commit messages (`feat:`, `refactor(helm):`, `docs:` …).
- Prefer editing existing files over creating new ones; keep modules small and domain-focused.
- No comments unless the *why* is non-obvious. Don't restate what well-named code does.
- For UI work, the reference design system is Noora (already in `deps/`). Reference layouts and patterns from `../tuist/server` and `../atlas` when in doubt.
- Tests live under `test/hive_web/...` mirroring `lib/hive_web/...` paths.

## Deployment

`main` auto-deploys via `.github/workflows/deploy.yml`: builds + pushes `ghcr.io/tuist/hive`, then `helm upgrade --install` against the `hive-production` cluster with the production overlay. Secrets come from 1Password (vault `hive-k8s-production`) via External Secrets Operator.

The chart is generic by default — Tuist-specific values (host, allowed domains, ESO config, hcloud storage, 1Password remote refs) live in `infra/helm/hive/values-production.yaml`. Anyone deploying their own Hive doesn't load that file.

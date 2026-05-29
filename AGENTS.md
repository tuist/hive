# Hive

Phoenix application that hosts Tuist's agentic product orchestration. MPL-2.0 licensed; runs as a single deployment per organization (Tuist hosts its own at `hive.tuist.dev`; the chart in `infra/helm/hive` supports self-hosting).

**This is an open-source repository.** Treat every commit and PR as world-readable. Never paste credentials, tokens, kubeconfigs, OAuth secrets, database URLs, or `.env` contents into source, tests, fixtures, commit messages, or PR bodies. Production secrets live exclusively in the `hive-k8s-production` 1Password vault and are pulled into Kubernetes via External Secrets at deploy time — the repo only references them by name (`hive-google-oauth/credential`), never by value. Reference names are not secrets but treat them as low-stakes signal: assume an attacker reading the repo learns them. Test fixtures and example env values must use obvious placeholders (e.g. `"client-id"`, `"google-client-secret"`), never real credentials even if revoked.

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

Auth is delegated to [Ueberauth] + [ueberauth_oidcc] (an OIDC strategy built on the `oidcc` library, which auto-discovers each provider's endpoints from `.well-known/openid-configuration`). `config/runtime.exs` reads env vars and registers issuers + strategies; `Hive.Auth` exposes only what the app's UI and callback need (`enabled?/0`, `providers/0`, `check_domain/2`, `current_user/1`).

[Ueberauth]: https://github.com/ueberauth/ueberauth
[ueberauth_oidcc]: https://github.com/erlef/ueberauth_oidcc

Two providers are supported and can run side-by-side:

- **Google** — preset on `https://accounts.google.com`; needs `HIVE_GOOGLE_CLIENT_ID/_SECRET`. `HIVE_GOOGLE_ALLOWED_DOMAINS` with a single domain also pushes Google's `hd=` hint to the authorize redirect.
- **Generic OIDC** — point `HIVE_OIDC_ISSUER` at any issuer URL with a `.well-known/openid-configuration`; supply `HIVE_OIDC_CLIENT_ID/_SECRET` (and optionally `HIVE_OIDC_DISPLAY_NAME`).

Routes: Ueberauth's plug owns `/auth/:provider` (redirect to IdP) and `/auth/:provider/callback` (token exchange + userinfo). The Hive `AuthController.callback/2` action reads `conn.assigns.ueberauth_auth`, runs `Hive.Auth.check_domain/2` against the provider's allowlist, and stores the user in the session.

## Conventions

- Conventional Commits for PR titles and commit messages (`feat:`, `refactor(helm):`, `docs:` …).
- Prefer editing existing files over creating new ones; keep modules small and domain-focused.
- No comments unless the *why* is non-obvious. Don't restate what well-named code does.
- For UI work, the reference design system is Noora (already in `deps/`). Reference layouts and patterns from `../tuist/server` and `../atlas` when in doubt.
- Tests live under `test/hive_web/...` mirroring `lib/hive_web/...` paths.

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

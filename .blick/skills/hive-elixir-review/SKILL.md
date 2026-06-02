---
name: hive-elixir-review
description: Project-specific PR-review rules for the tuist/hive Phoenix/Elixir codebase. Focuses on open-source secret hygiene, Noora data-part styling, OIDC auth, async tests, Helm deployment boundaries, and release conventions documented in AGENTS.md.
---

# Hive Elixir Review

This skill is intentionally narrow. **Generic Elixir style, naming,
formatting, pipe chains, and low-level Credo concerns are already covered
by `mix format` and `mix credo` in CI. Do not flag those.** Focus on the
rules below because they catch Hive-specific regressions.

For each finding, cite `path:line` or `Module.function/arity` and quote
the relevant snippet.

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

## 4. Async tests and config isolation

All tests in Hive are expected to be `async: true`. Tests must not mutate
global application config in `setup` or `on_exit`; use Mimic on a
wrapping module instead.

### Flag

- New test modules that omit `async: true` or set `async: false`.
  **Severity: medium.**
- Tests that call `Application.put_env/3`, `Application.delete_env/2`, or
  similar global config mutation to control code under test.
  **Severity: high.**
- A new mockable module used with Mimic that is not copied in
  `test/test_helper.exs`. **Severity: medium.**
- Tests for route/controller changes that are not mirrored under the
  matching `test/hive_web/...` path. **Severity: low.**

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

## 7. Phoenix shape

Hive currently uses Phoenix controllers and raw HEEx templates, not
LiveView.

### Flag

- New LiveView code introduced without an accompanying architectural
  reason and route/layout integration. **Severity: medium.**
- New controller actions or templates that skip the existing
  `Layouts.app` / `Layouts.dashboard` structure when they are part of
  the normal app shell. **Severity: medium.**
- New domain behavior placed in controllers instead of a small module
  under `lib/hive/`. **Severity: medium.**

### Do not flag

- Existing controller-rendered HEEx templates. That is the current app
  model.

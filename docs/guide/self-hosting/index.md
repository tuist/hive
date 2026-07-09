# Overview

The way product teams shape work has not kept up with how the work
itself is done. Tickets, plans, and operational alerts each live in a
different tool, and the loop between "what we want to build", "what we
agreed to build", and "what is actually happening in production" only
exists in the heads of the people who happen to be in the room.

That gap matters more as coding agents and
[large language model](https://en.wikipedia.org/wiki/Large_language_model)-driven
workflows enter the picture. Agents need the same context that humans rely on, but
that context is scattered across spec docs, project trackers,
dashboards, and chat threads. Each tool understands only its own slice.

Hive is a single web service that holds the shape of product work in
one place:

- **Projects** group everything by product, codebase, or service the
  instance tracks, such as [Atlas](https://github.com/tuist/atlas),
  [Hive](https://github.com/tuist/hive),
  [Tuist](https://github.com/tuist/tuist),
  [Kura](https://github.com/tuist/kura),
  [Noora](https://github.com/tuist/Noora), or
  [Once](https://github.com/tuist/once).
  A project owns its linked GitHub repositories and the Really Simple
  Syndication ([RSS](https://www.rssboard.org/rss-specification)) sources
  that feed it.
- **Domains** are reusable classification tags that can be associated
  with one or more projects. A single-product instance can keep zero
  domains; a multi-domain project can carry several, and a shared
  domain can belong to multiple projects.
- **Specs** capture intent, decisions, and the surface area of a piece
  of work in a form both humans and agents can read. Each spec belongs
  to one project, inherits that project's visibility, and can only be
  narrowed to private visibility.
- **Forage** brings feature requests, bug reports, feedback, GitHub
  issues, and Grafana alerts into one triage queue. GitHub issues are
  classified into project domains; Grafana alerts arrive through
  project webhooks.
- **Drops** aggregate shipped updates (GitHub releases and changelog
  feeds) into a stream subscribers can follow per project or per
  domain.

The goal is a small, opinionated surface that a team can adopt without
adopting an entire methodology.

The rest of this guide is written for people who want to set up a Hive
instance and understand how teams use the product day to day.

## How it ships

Hive is licensed under the Mozilla Public License 2.0
([MPL-2.0](https://www.mozilla.org/en-US/MPL/2.0/)) and ships as a
single image plus a generic Helm chart. The container image lives at
[`ghcr.io/tuist/hive`](https://github.com/orgs/tuist/packages/container/package/hive)
and the Helm chart at
[`oci://ghcr.io/tuist/charts/hive`](https://github.com/orgs/tuist/packages/container/package/charts%2Fhive).
Both artifacts are released from the [tuist/hive](https://github.com/tuist/hive)
repository on every push to `main`. Tuist runs the canonical instance
at [hive.tuist.dev](https://hive.tuist.dev), but the same artifacts let
any team self-host.

## Next

- [Configuration reference](/reference/configuration) lists the runtime
  environment variables operators can set.
- [Authentication](./authentication) explains how to wire up Google and
  generic OpenID Connect
  ([OIDC](https://openid.net/developers/how-connect-works/)) providers.
- [Authorization](./authorization) covers the roles each user can hold
  and what they can see.
- [Model gateway](./inference) covers OpenAI-compatible automation
  clients, model-bound tokens, and the
  [large language model](https://en.wikipedia.org/wiki/Large_language_model)-backed
  workflows that activate when a provider key is configured.
- [Drops](./drops) describes the shipped-updates surface and how
  releases and changelogs feed into it.
- [Slack](./slack) covers connecting Slack workspaces so Hive can reply
  in threads and capture messages as forage items through the
  Ops-managed intake destination.
- [Deployment](./deployment) walks through what you need to deploy
  Hive, the visibility model, and the Helm chart values to provide.

## Overview

The way product teams shape work has not kept up with how the work
itself is done. Tickets, plans, and operational alerts each live in a
different tool, and the loop between "what we want to build", "what we
agreed to build", and "what is actually happening in production" only
exists in the heads of the people who happen to be in the room.

That gap matters more as coding agents and LLM-driven workflows enter
the picture. Agents need the same context that humans rely on, but
that context is scattered across spec docs, project trackers,
dashboards, and chat threads. Each tool understands only its own slice.

Hive is a single web service that holds the shape of product work in
one place:

- **Projects** group everything by product, codebase, or service the
  instance tracks. A project owns its connected GitHub repositories
  and the RSS sources that feed it.
- **Meadows** are optional sub-domains *inside* a project, so a team
  can split a project into smaller buckets the classifier routes
  issues and drops into. A single-product instance can keep zero
  meadows; a multi-domain project can carry several.
- **Specs** capture intent, decisions, and the surface area of a piece
  of work in a form both humans and agents can read.
- **Forage** brings feature requests, bug reports, feedback, GitHub
  issues, and Grafana alerts into one triage queue, scoped to the
  meadows each viewer can see.
- **Drops** aggregate shipped updates (GitHub releases and changelog
  feeds) into a stream subscribers can follow per project or per
  meadow.

The goal is a small, opinionated surface that a team can adopt without
adopting an entire methodology.

## How it ships

Hive is licensed under MPL-2.0 and ships as a single image plus a
generic Helm chart. The container image lives at `ghcr.io/tuist/hive`
and the Helm chart at `oci://ghcr.io/tuist/charts/hive`. Both artifacts
are released from the [tuist/hive](https://github.com/tuist/hive)
repository on every push to `main`. Tuist runs the canonical instance
at [hive.tuist.dev](https://hive.tuist.dev), but the same artifacts let
any team self-host.

## Next

- [Authentication](./authentication) explains how to wire up Google and
  generic OIDC providers.
- [Authorization](./authorization) covers the roles each user can hold
  and what they can see.
- [Agents](./agents) covers the LLM-backed workflows that activate when
  an API key is configured.
- [Drops](./drops) describes the shipped-updates surface and how
  releases and changelogs feed into it.
- [Slack](./slack) covers connecting Slack workspaces so Hive can reply
  in threads and capture messages as feature requests.
- [Deployment](./deployment) walks through what you need to deploy
  Hive, the visibility model, and the Helm chart values to provide.

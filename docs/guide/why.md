## Why Hive

The way product teams shape work has not kept up with how the work
itself is done. Tickets, plans, and operational alerts each live in a
different tool, and the loop between "what we want to build", "what we
agreed to build", and "what is actually happening in production" only
exists in the heads of the people who happen to be in the room.

That gap matters more as coding agents and LLM-driven workflows enter
the picture. Agents need the same context that humans rely on, but
that context is scattered across spec docs, project trackers,
dashboards, and chat threads. Each tool understands only its own slice.

## Hive Holds The Shape Of Product Work

Hive is a single Phoenix application that holds the shape of product
work in one place:

- **Specs** capture intent, decisions, and the surface area of a piece
  of work in a form both humans and agents can read.
- **Forage** ingests operational signals such as Grafana alerts and
  threads them per meadow, so the same view that holds the plan also
  holds the operational reality.
- **Authentication** is delegated to OIDC providers so any team's
  identity setup works without bespoke integrations.

The goal is a small, opinionated surface that a team can adopt without
adopting an entire methodology.

## Run It Where You Want

Hive is licensed under MPL-2.0 and ships as a single image plus a
generic Helm chart. Tuist runs the canonical instance at
[hive.tuist.dev](https://hive.tuist.dev), but the same artifacts let
any team self-host.

Read [Self-hosting](/guide/self-hosting/) to see the moving parts and
the minimum config you need to bring it up.

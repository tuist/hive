# Overview

Hive is a shared home for product signals, plans, and shipped work. It
connects the feedback arriving today with the decisions a team makes and
the improvements people can use later.

## How work moves through Hive

Hive uses five concepts:

1. **Projects** represent a product, codebase, or service. A project owns
   the repositories and incoming sources that belong to it.
2. **Domains** describe durable product areas that can span more than one
   project. They let people follow a concern such as authentication,
   performance, or developer experience across the organization.
3. **Forage** gathers feature requests, bug reports, feedback, GitHub
   issues, and Grafana alerts into one queue.
4. **Specs** turn those signals into proposals. A spec records the
   intended outcome, its current status, revisions, and discussion.
5. **Drops** show the user-facing improvements that shipped and connect
   them back to projects, domains, and supporting work.

This creates a loop from evidence to intent to delivery. Teams can use
only the parts they need without adopting a separate product methodology.

## Choose your path

If your organization already runs Hive, start with the product guide:

- [Projects](/guide/using-hive/projects) explains the top-level boundary
  for repositories, domains, specs, and releases.
- [Forage](/guide/using-hive/forage) shows how to submit and triage product
  signals.
- [Specs](/guide/using-hive/specs) covers proposals, revisions, comments,
  and review requests.
- [Drops](./drops) explains how to follow shipped improvements.

If you operate Hive for your organization, start with
[Install Hive](./installation), then configure
[authentication](./authentication) and review
[authorization](./authorization).

## How Hive is distributed

Hive is licensed under the
[Mozilla Public License 2.0](https://www.mozilla.org/en-US/MPL/2.0/) and
is distributed as a container image. Tuist runs a public instance at
[hive.tuist.dev](https://hive.tuist.dev), and any organization can deploy
the same software on its own infrastructure.

The container image is published as
[`ghcr.io/tuist/hive`](https://github.com/orgs/tuist/packages/container/package/hive).

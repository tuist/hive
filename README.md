<p align="center">
  <img src="priv/static/images/logo.png" alt="Hive" width="20%" />
</p>

<h1 align="center">Hive</h1>

<p align="center">
  <a href="https://github.com/tuist/hive/actions/workflows/hive.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/tuist/hive/hive.yml?branch=main&label=ci&style=flat-square" alt="CI" />
  </a>
  <a href="https://github.com/tuist/hive/actions/workflows/deploy.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/tuist/hive/deploy.yml?branch=main&label=deploy&style=flat-square" alt="Deployment" />
  </a>
  <a href="https://github.com/tuist/hive/actions/workflows/docs.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/tuist/hive/docs.yml?branch=main&label=docs&style=flat-square" alt="Docs" />
  </a>
  <a href="https://github.com/tuist/hive/releases">
    <img src="https://img.shields.io/github/v/release/tuist/hive?label=release&style=flat-square" alt="Latest release" />
  </a>
  <a href="LICENSE.md">
    <img src="https://img.shields.io/github/license/tuist/hive?style=flat-square" alt="MPL-2.0 license" />
  </a>
</p>

At Tuist we've reimagined how we shape and build product by leaning into
LLMs and agentic workflows, and Hive is our take on it. It's built to run
inside our own team and equally to be opened up to the people who use
your products.

When an LLM is configured, Hive can continuously evolve its meadows from
new forage items and specs, keeping the taxonomy aligned with durable
Tuist business domains instead of one-off tickets or vague buckets.

Hive can also connect Slack workspaces. Instance admins manage workspace
installs, and signed-in users can turn Slack messages into forage items
or receive bot replies in Slack threads.

Hive is licensed under [MPL-2.0](LICENSE.md). We don't offer it as a
managed service, but you can try our own instance, or self-host your own.

## Projects and meadows

Hive separates *what* the instance tracks from *how* you slice it.

A **project** is the top-level grouping: a product, codebase, or
service the instance tracks (for example Tuist, Atlas, Hive, Once). Projects
own their connected GitHub repositories and the RSS sources that feed
their drops. The list of projects lives at `/projects`.

A **meadow** is an optional sub-domain *inside* a project, so a team
can split an instance into smaller buckets the classifier routes
issues and drops into. The Tuist project, for instance, may carry
meadows like `Cache` or `Generated projects`; a single-product Hive
(the Kura case) can keep zero meadows and surface everything at the
project level. Meadows still appear at `/meadows`.

## Forage

Forage is a single queue for feature requests, bug reports, feedback,
GitHub issues, and Grafana alerts. Signed-in users can create forage
items, edit the items they created, and comment on manual forage items
from Hive. GitHub issue items show the issue discussion from GitHub so
reviewers can read the latest thread without Hive storing a second copy.

## Drops

Drops aggregate shipped updates so people can follow what each meadow
has actually released. Two sources feed it:

- **GitHub Releases** are ingested automatically from every repository
  connected to a project. Hive asks an agent to traverse the release
  body's referenced URLs, fetch the linked context, and turn the
  user-facing improvements it can support into drops. The release itself
  is not shown as a drop.
- **RSS / Atom changelog feeds** can be registered per meadow from
  `/ops/drops` (admin only). Hive polls every enabled feed every 15
  minutes and merges its entries into the drops timeline.

Drops are visible everywhere meadows are: drops from public meadows are
visible to anyone, drops from private meadows are visible to
organization members. The `/drops` index supports filtering by meadow
and source type. Each meadow's drops also surface through the existing
per-meadow merged feed at `/meadows/:id/atom.xml`.

## Our instance

Tuist runs the canonical Hive instance at
[hive.tuist.dev](https://hive.tuist.dev). It is the easiest way to see
Hive in action and to follow along with how we shape product work at
Tuist.

## Subscribe

Every list-style surface ships both an Atom 1.0 feed at
`<path>/atom.xml` and an RSS 2.0 feed at `<path>/rss.xml`, so you can
subscribe with any reader. Each page surfaces the feeds in two places:
a small RSS dropdown next to the page title with both links, and the
usual `<link rel="alternate">` discovery tags in the document head so
readers can auto-detect them from the page URL. Visibility is enforced
the same way as the HTML page: anonymous subscribers only see the
items a logged-out visitor would see.

Available feeds (replace `atom.xml` with `rss.xml` for the RSS 2.0
version):

- `/forage/atom.xml` — feature requests, bug reports, feedback, GitHub
  issues, and Grafana alerts visible to the subscriber.
- `/specs/atom.xml`
- `/drops/atom.xml` — shipped updates across every meadow. Add
  `?meadow_ids=<id>,<id>` to subscribe only to drops from a subset of
  meadows.
- `/meadows/:id/atom.xml` — the GitHub issues, Grafana alerts, and
  drops that belong to one meadow, merged into a single timeline.
- `/meadows/:id/drops/atom.xml` — only the drops for a single meadow.

## Slack

Hive connects to Slack through one Slack app per Hive deployment. Set
`HIVE_SLACK_CLIENT_ID`, `HIVE_SLACK_CLIENT_SECRET`, and
`HIVE_SLACK_SIGNING_SECRET`, then configure the Slack app with these
URLs:

- OAuth redirect URL: `https://<your-hive-host>/slack/install/callback`
- Event subscriptions request URL: `https://<your-hive-host>/api/slack/events`
- Interactivity request URL: `https://<your-hive-host>/api/slack/interactions`

For Tuist's instance, replace `<your-hive-host>` with `hive.tuist.dev`.
To install the same app in workspaces beyond the app's development
workspace, enable Slack Public Distribution. App Directory submission is
not required for private install links. Instance admins manage workspace
installs from `/ops/slack`.

## Documentation

Read the documentation at
[docs.hive.tuist.dev](https://docs.hive.tuist.dev) to learn more about
how Hive works and how to self-host it.

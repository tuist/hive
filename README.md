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

Hive can also connect Slack workspaces so organization members can turn
Slack messages into feature requests and receive bot replies in Slack
threads.

Hive is licensed under [MPL-2.0](LICENSE.md). We don't offer it as a
managed service, but you can try our own instance, or self-host your own.

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

- `/forage/feature-requests/atom.xml`
- `/forage/github-issues/atom.xml`
- `/forage/grafana-alerts/atom.xml` (organization members only)
- `/specs/atom.xml`
- `/meadows/:id/atom.xml` — the GitHub issues and Grafana alerts that
  belong to one meadow, merged into a single timeline.

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
not required for private install links.

## Documentation

Read the documentation at
[docs.hive.tuist.dev](https://docs.hive.tuist.dev) to learn more about
how Hive works and how to self-host it.

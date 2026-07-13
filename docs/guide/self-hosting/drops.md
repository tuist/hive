# Drops

Drops aggregate shipped updates so people can follow what each domain
has actually released. A drop is a single user-facing update, for
example a shipped feature, a fix, or a changelog entry, optionally
tagged with a version (`v0.25.0`, `4.7.0`). Drops are read-only from
the dashboard: the entries are produced by ingestion, not by humans
typing into a form.

Each drop gets a public number. Hive uses `/drops/:number` for the
shareable drop page instead of exposing the internal database
identifier.

## Sources

Two source types feed drops:

- **GitHub Releases**: every release published on a repository
  connected to a project is ingested automatically. New releases appear
  in `/drops` within fifteen minutes, attached to the domains associated
  with the release repository's project.
- **RSS / Atom changelog feeds**: any public RSS or Atom feed can be
  registered as a source from `/ops/drops` (admin only). Sources are
  registered for a project, not a domain. Hive polls every enabled feed
  on the same fifteen-minute interval and routes every ingested entry
  through the classifier for that project's associated domains.

## Routing entries to domains

Each new entry is processed by a classifier that decides which domains
it belongs to. The classifier reads the entry's title and body,
compares them against the description of each candidate domain, and
links the drop to the domains whose substance it actually matches. A
single entry can end up linked to zero, one, or several domains.

When a model provider is configured (see
[Model gateway](./inference#agentic-workflows)) the classifier asks the
agent to pick the right subset. When no model provider is configured,
the classifier falls back to linking the entry to every domain so the
dashboard still has something to show; this matches the fallback used for
GitHub issue classification. A sweeper retries any drop still missing a
classification, so transient model-provider failures and drops created
before classification shipped recover on the next tick.

## Rewriting GitHub releases

GitHub release notes are written for contributors. They tend to
reference pull-request numbers, author handles, internal labels, and
process artefacts that are not useful to someone trying to find out
what changed for them. When a model provider is configured, Hive
rewrites each release into a user-facing markdown changelog before it
surfaces as a drop, following the linked issues and pull requests to
ground every bullet in what those pages actually say.

The original release body is preserved. If the upstream release notes
change later, the rewrite is invalidated and re-runs on the next sync.
When no model provider is configured, drops keep showing the raw release
notes unchanged, so deploying without a model provider is fine.

Each generated release drop is also linked to any GitHub issue or pull
request that grounded it when that repository is connected to Hive. The
linked GitHub record is kept as a forage item even after it closes, so
Hive can answer which release addressed a given forage item.

## Weekly digest

Hive turns each Monday-to-Friday workweek into one narrated
edition. `/drops/digest` lists the published editions in a searchable,
year-filtered, paginated table. Selecting an edition opens its narration
at `/drops/digest/<week-start>`. Each edition connects the most meaningful
changes into a point of view about the week instead of repeating the
timeline as a list.

The language-model agent connects the public drops from that week into a
cohesive narration. Claims and links come from the Drops timeline, and
generated prose never uses em dashes.

Only drops visible to an anonymous visitor enter an edition. Private
domain work is never sent to the agent or published in the digest. Hive
generates the current edition every Friday at 17:00 Coordinated Universal
Time. When the application starts, it checks the latest workweek whose
Friday publication time has passed. This catches up a missed edition without
publishing the current week early. Empty weeks are recorded without calling
the model, and a completed or empty week is not evaluated again.

When language-model inference is not configured, weekly generation
stays dormant while the Drops timeline and its regular feeds continue
to work.

## Subscribing

Every list-style surface in Hive ships an Atom 1.0 feed at
`<path>/atom.xml` and a
[Really Simple Syndication (RSS) 2.0 feed](https://www.rssboard.org/rss-specification)
at `<path>/rss.xml`. Drops are no exception:

- `/drops/atom.xml`: every drop the subscriber is allowed to see.
- `/drops/atom.xml?project_ids=<id>,<id>`: only drops from the listed
  projects.
- `/drops/atom.xml?domain_ids=<id>,<id>`: only drops linked to the
  listed domains.
- `/drops/atom.xml?project_ids=<id>&domain_ids=<id>`: only drops that
  match both the selected projects and selected domains.
- `/projects/:id/drops/atom.xml`: only the drops for one project.
- `/domains/:id/drops/atom.xml`: only the drops for one domain.
- `/domains/:id/atom.xml`: the domain's merged feed (GitHub issues,
  Grafana alerts tagged with that domain, and drops together).
- `/drops/digest/atom.xml`: narrated weekly editions with the full
  digest body.

Replace `atom.xml` with `rss.xml` for the RSS 2.0 version. Visibility
is enforced the same way as the HTML page: anonymous subscribers only
see drops linked to a public domain.

The `Subscribe` button on `/drops` opens a picker that lets visitors
choose projects, domains, or both, generates the matching feed address
with the right query parameters, and exposes a copy button so the feed
address can go straight into a reader.

The **Weekly digest** button opens the latest edition. Its feed menu
exposes the Atom and RSS addresses for readers that prefer one connected
weekly update over individual drops.

## Managing RSS sources

Admins (users with the `admin` role; see [Authorization](./authorization))
manage RSS sources from `/ops/drops`. From the ops page admins can:

- Add a new source (feed address + optional label).
- Enable or disable a source. Disabled sources stay in the database
  but are skipped by the syncer.
- Trigger an immediate sync against a single source.
- Remove a source.

Every add, update, and removal is recorded in the audit trail.

# Feed reference

Hive exposes list content as Atom 1.0 and
[Really Simple Syndication 2.0](https://www.rssboard.org/rss-specification)
feeds. Feed visibility matches the corresponding dashboard page. An
anonymous reader never receives private or organization-only content.

Most pages include a **Subscribe** menu that provides the correct address
without requiring readers to construct it manually.

## Forage

| Content | Atom 1.0 | Really Simple Syndication 2.0 |
|---|---|---|
| All visible Forage items | `/forage/atom.xml` | `/forage/rss.xml` |
| Feature requests | `/forage/feature-requests/atom.xml` | `/forage/feature-requests/rss.xml` |
| GitHub issues | `/forage/github-issues/atom.xml` | `/forage/github-issues/rss.xml` |
| Grafana alerts | `/forage/grafana-alerts/atom.xml` | `/forage/grafana-alerts/rss.xml` |

## Flights

| Content | Atom 1.0 | Really Simple Syndication 2.0 |
|---|---|---|
| Member-visible Flight history | `/flights/atom.xml` | `/flights/rss.xml` |

Flight feeds require an organization-member session and never expose portable
agent sessions. Each entry links to its Flight detail page.

## Specs, postmortems, and Drops

| Content | Atom 1.0 | Really Simple Syndication 2.0 |
|---|---|---|
| Specs | `/specs/atom.xml` | `/specs/rss.xml` |
| Postmortems | `/postmortems/atom.xml` | `/postmortems/rss.xml` |
| Drops | `/drops/atom.xml` | `/drops/rss.xml` |
| Weekly drop digests | `/drops/digest/atom.xml` | `/drops/digest/rss.xml` |

The Drops subscription page can add `project_ids` and `domain_ids` query
parameters to the global feed. Use comma-separated identifiers to select
more than one project or domain. When both parameters are present, a drop
must match both selections.

## Project and domain feeds

| Content | Atom 1.0 | Really Simple Syndication 2.0 |
|---|---|---|
| Drops for one project | `/projects/:id/drops/atom.xml` | `/projects/:id/drops/rss.xml` |
| Drops for one domain | `/domains/:id/drops/atom.xml` | `/domains/:id/drops/rss.xml` |
| Combined activity for one domain | `/domains/:id/atom.xml` | `/domains/:id/rss.xml` |

Replace `:id` with the identifier shown in the page address. A combined
domain feed includes GitHub issues, Grafana alerts, and drops associated
with that domain.

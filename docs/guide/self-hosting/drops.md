# Drops

Drops show the user-facing improvements that shipped. A drop can
represent a feature, fix, or changelog entry and can carry a release
version.

Use Drops to follow what changed across the whole organization, one
project, or one domain.

## Where drops come from

Hive supports two sources:

- **GitHub releases** from repositories linked to projects.
- **Changelog feeds** registered by administrators under
  **Ops (Operations) → Drops**.

Hive checks enabled sources every fifteen minutes and when the application
starts. New items are associated with their project and then classified
against the domains linked to that project.

## Domain classification

When Hive has a configured language model, it compares each shipped
improvement with the descriptions of the project's domains and links the
best matches. One drop can belong to several domains or remain
unclassified.

Without language-model configuration, Hive links the drop to every domain
associated with the project. This keeps the timeline useful while making
the broader classification visible.

## GitHub release improvements

When language-model workflows are enabled, Hive turns a GitHub release
into one drop per user-facing improvement. It can use referenced issues,
pull requests, changelog entries, and documentation to explain what
changed in product language.

Without language-model configuration, GitHub release generation stays
dormant. Changelog feed entries continue to appear normally.

See [Model gateway](./inference#agentic-workflows) for the workflows that
become active.

## Weekly digest

Hive publishes a narrated edition for each Monday-to-Friday workweek.
Open **Weekly digest** from the Drops page to browse editions.

Only drops visible to an anonymous visitor are included. Private-domain
work is excluded before the edition is written. Hive publishes on Friday
at 17:00 Coordinated Universal Time and catches up the most recent missed
edition after an application restart.

Weekly generation remains inactive when no language model is configured.
The regular Drops timeline and feeds still work.

## Subscribe

Select **Subscribe** on the Drops page to choose projects, domains, or
both. Hive creates the matching Atom 1.0 and Really Simple Syndication
feed addresses and provides a copy button.

The weekly digest has its own feed for readers who prefer one connected
summary instead of individual drops. See the [feed reference](/reference/feeds)
for all available addresses.

## Manage changelog feeds

Administrators can open **Ops (Operations) → Drops** to:

- Add a public Atom or Really Simple Syndication source to a project.
- Enable or disable an existing source.
- Request an immediate synchronization.
- Remove a source that should no longer be checked.

Changes to sources are recorded in the [audit trail](./audit).

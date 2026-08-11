# Postmortems

Postmortems are published accounts of incidents and what the team learned
from them. They keep the incident narrative, affected domains, and follow-up
work together in one place.

## Publish a postmortem

Organization members can open **Postmortems** and select **Publish
postmortem**. Write the complete account in Markdown and use a level-one
heading for its title:

```markdown
# Tuist registry outage
```

Hive uses the first level-one heading as the display title. Each postmortem
also receives an incremental number, so people can refer to it with a stable
label such as **Postmortem #12**.

Select one or more domains to connect the incident to the affected product
areas. The postmortem page shows its author, publication date, domains, and
action-item progress in a summary above the full Markdown document.

## Choose visibility

A public postmortem is readable without signing in and can only be associated
with public domains. A private postmortem is visible only to organization
members and administrators and can include private domains.

Public postmortems can also appear in subscription feeds and link previews.
Private content is excluded whenever the reader is not signed in.

## Track action items

Organization members can add action items from a postmortem page. Each item
has a title and an optional description. Members can edit or delete an item,
mark it completed, or reopen it when more work is required.

Readers can see the action items and their current status. Management controls
only appear for people who can edit the postmortem.

## Find related incidents

The Postmortems page supports text search, publication-date filters, and
pagination. Domains provide another way to discover incidents that affected
the same product area.

When the [model gateway](/guide/self-hosting/inference#agentic-workflows) is
configured, Hive also prepares each published postmortem for semantic
retrieval. Unchanged content is not processed again, while an edited document
is indexed from its latest content.

## Subscribe

The Postmortems page exposes
[Atom](https://www.rfc-editor.org/rfc/rfc4287) and
[RSS](https://www.rssboard.org/rss-specification "Really Simple Syndication")
feeds for the postmortems visible to the reader. Use the **Subscribe** menu on
the page, or see the [feed reference](/reference/feeds) for the feed addresses.

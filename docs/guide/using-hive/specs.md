# Specs

Specs are editable proposals that turn product signals into shared
intent. They record what should change, why it matters, the current
decision state, and the discussion around it.

## Create a spec

Organization members can create a spec directly from **Specs → New
spec**, or select **Create spec** from a Forage item.

Every spec belongs to a project. A spec can also link to any domains
associated with that project.

Provide:

- A title that states the proposed outcome.
- A Markdown body with the context, decision, and important constraints.
- A status that reflects where the proposal is in its lifecycle.
- Optional domains that help people discover related work.

## Use statuses consistently

Hive supports these statuses:

- **Draft** while the proposal is still being shaped.
- **Proposed** when it is ready for a decision.
- **Approved** when the direction has been accepted.
- **In progress** while implementation is underway.
- **Shipped** when the outcome is available to users.
- **Paused**, **Rejected**, and **Archived** when work is no longer
  moving through the active path.

The status should describe the proposal, not an individual implementation
task.

## Review revisions and comments

Every saved edit creates a revision in **Draft history**. Readers can see
who edited the spec, when it changed, and a summary of the change.

Signed-in users can comment on visible specs. Comment authors can edit or
delete their own comments, and each comment has a stable link for sharing
review context.

When Slack notifications are configured, an organization member can
select **Ask for review**. Hive posts the latest proposal and focused
review prompts to the configured channel.

## Understand visibility

A spec inherits its project's visibility by default. A spec in a public
project can be narrowed to private. A spec in a private project cannot be
made public.

Private specs are visible only to organization members and
administrators. Their content is excluded from public feeds and Slack
link previews.

## Subscribe

The Specs page exposes Atom 1.0 and Really Simple Syndication feeds for
visible specs. See the [feed reference](/reference/feeds) for details.

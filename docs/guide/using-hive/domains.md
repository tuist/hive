# Domains

Domains are durable product or engineering areas that organize work
across projects. Examples include authentication, performance, command
line experience, or generated projects.

Use a domain when people should be able to follow the same concern across
several repositories or products. Avoid creating a domain for a single
ticket, release, or short-lived initiative.

## Create a domain

Organization members can open **Domains**, select **Add domain**, and
provide:

- A concise name that people will recognize in lists and badges.
- A description that explains what belongs in the domain and what does
  not.

Domains created from the dashboard are public. Connected clients can
create private domains for organization-only work.

The description matters when language-model classification is enabled.
Hive uses it to decide whether issues, releases, and other signals belong
to the domain.

## Connect domains to projects

Open a project and select **Link domain**. A domain can belong to more
than one project, while each repository still belongs to one project.

This separation lets a shared concern span multiple codebases without
duplicating the domain. It also limits classification to domains that are
relevant to the source project.

## Use domains throughout Hive

Domains appear on Forage items, specs, postmortems, and drops. They
provide a stable way to answer questions such as:

- What signals are arriving for this product area?
- Which proposals are currently active?
- What did we learn from recent incidents?
- What improvements shipped recently?

The domain page combines those signals and exposes subscription feeds.
See the [feed reference](/reference/feeds) for the available formats.

## Automatic domain evolution

When an administrator configures Hive's language-model workflows, Hive
can automatically create new domains and improve existing descriptions
from recent work. It does not delete domains or change their visibility.

See [Model gateway](/guide/self-hosting/inference#agentic-workflows) for
the workflows that become active.

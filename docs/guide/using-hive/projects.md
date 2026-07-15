# Projects

Projects are the top-level boundary in Hive. Create one for each product,
codebase, or service whose work should be tracked together.

A project owns:

- The GitHub repositories that supply issues and releases.
- The domains used to classify work from those repositories.
- The specs written for the project.
- The incoming alert addresses created for the project.
- The shipped updates and subscriptions associated with it.

## Create a project

Organization members can open **Projects**, select **Add project**, and
provide a name, description, and visibility.

- **Public** projects and their public content can be viewed without
  signing in when the Hive instance is public.
- **Private** projects are visible only to organization members and
  administrators.

Choose a name that remains useful as the organization changes. Product
or service names usually work better than temporary initiative names.

## Connect a repository

Configure the [GitHub integration](/guide/self-hosting/github) first.
Then open a project and select **Link repository**. Hive lists the
repositories available to the configured GitHub installation.

Once linked, Hive can:

- Mirror open issues into Forage.
- Ingest published releases into Drops.
- Create GitHub issues when the administrator chooses GitHub as the
  Forage intake destination.

Removing a repository stops future synchronization. It does not delete
the repository on GitHub.

## Link domains

Domains are reusable, so the same domain can belong to several projects.
Open the project and select **Link domain** to attach an existing domain.

Repository issues and releases are classified only against domains linked
to their project. See [Domains](./domains) for guidance on choosing useful
domain boundaries.

## Receive Grafana alerts

Open the project's **Webhooks** section and create a Grafana webhook.
Hive shows the generated address once. Copy it into a Grafana contact
point before dismissing the message.

Grafana sends firing and resolved alerts to the same address. Hive keeps
their latest state in Forage and associates them with the project.

## Follow a project

The project page exposes Atom 1.0 and Really Simple Syndication feeds for
its shipped updates. See the [feed reference](/reference/feeds) for the
addresses and visibility behavior.

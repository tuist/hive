# GitHub

Hive uses a GitHub App to list repositories, mirror issues, ingest releases,
optionally create issues from Forage, publish Flight reports as issue comments,
and publish pull requests from Fix Flights. This connection is separate from
GitHub sign-in, which is configured under
[Authentication](./authentication#github).

## Create and install the GitHub App

Create a GitHub App for the organization that owns the repositories Hive
will track. Use your Hive instance as the homepage and install the app on
the repositories you want Hive to access.

Grant these repository permissions:

- **Metadata: read-only** to identify installed repositories.
- **Contents: read-only** to read published releases. Choose **read and
  write** when members will run the coding harness, because Hive creates the
  resulting branch and commit.
- **Issues: read and write** to mirror issues, create Forage issues, and publish
  Flight reports as comments.
- **Pull requests: read-only** so release evidence can include referenced
  pull requests. Choose **read and write** when members will run the coding
  harness, because Hive opens the resulting pull request.

Set the app's webhook address to `https://<hive-host>/webhooks/github`, choose a
webhook secret, and subscribe to **Pull request** events. Hive uses these
signed events to resolve errors referenced by merged pull requests.

After installing the app, record its app identifier, installation
identifier, and private key. The private key can be supplied in Privacy
Enhanced Mail format or as a base64-encoded value.

## Configure Hive

Set these values in the Hive deployment secret:

- [`HIVE_GITHUB_APP_ID`](/reference/configuration#hive_github_app_id)
- [`HIVE_GITHUB_APP_INSTALLATION_ID`](/reference/configuration#hive_github_app_installation_id)
- [`HIVE_GITHUB_APP_PRIVATE_KEY`](/reference/configuration#hive_github_app_private_key)
- [`HIVE_GITHUB_WEBHOOK_SECRET`](/reference/configuration#hive_github_webhook_secret)

Restart the Hive deployment after adding the values. Keep the private key
in a secret manager and never place it in a values file.

## Link repositories to projects

Open a project and select **Link repository**. Hive shows repositories
available to the installed GitHub App. A repository can belong to one
Hive project.

After linking:

- Open issues appear in Forage on the next synchronization.
- Published releases feed Drops.
- Repository labels become available when GitHub is the Forage intake
  destination.
- Grafana alerts and mirrored GitHub issues can start a Flight against the
  repository when the Flight runner and Hive inference are also configured.
- Merged pull requests resolve error issues when their descriptions include
  the error's Hive link. Hive only resolves an error belonging to the project
  linked to that repository.

Hive synchronizes issues and releases every fifteen minutes. It also
runs synchronization when the application starts.

## Choose the Forage intake destination

Administrators can open **Ops (Operations) → Forage** and select a linked
repository as the destination for new Forage items. Dashboard, Slack,
and connected-client submissions then create issues in that repository.

Choose **Hive-managed item** instead when product signals should stay in
Hive.

## Troubleshooting

If a repository does not appear in the project picker:

1. Confirm that the GitHub App is installed on that repository.
2. Confirm that all three deployment values are present.
3. Restart the Hive deployment after changing the private key or
   installation.
4. Check that the installation still grants the permissions listed
   above.

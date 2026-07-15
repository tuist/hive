# GitHub

Hive uses a GitHub App to list repositories, mirror issues, ingest
releases, and optionally create issues from Forage. This connection is
separate from GitHub sign-in, which is configured under
[Authentication](./authentication#github).

## Create and install the GitHub App

Create a GitHub App for the organization that owns the repositories Hive
will track. Use your Hive instance as the homepage and install the app on
the repositories you want Hive to access.

Grant these repository permissions:

- **Metadata: read-only** to identify installed repositories.
- **Contents: read-only** to read published releases.
- **Issues: read and write** to mirror issues and create Forage issues.
- **Pull requests: read-only** so release evidence can include referenced
  pull requests.

After installing the app, record its app identifier, installation
identifier, and private key. The private key can be supplied in Privacy
Enhanced Mail format or as a base64-encoded value.

## Configure Hive

Set these values in the Hive deployment secret:

- [`HIVE_GITHUB_APP_ID`](/reference/configuration#hive_github_app_id)
- [`HIVE_GITHUB_APP_INSTALLATION_ID`](/reference/configuration#hive_github_app_installation_id)
- [`HIVE_GITHUB_APP_PRIVATE_KEY`](/reference/configuration#hive_github_app_private_key)

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

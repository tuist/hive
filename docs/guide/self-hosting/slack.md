# Slack

Connect Slack when people should be able to discuss Hive work where
their team already communicates.

Once connected, Hive can:

- Reply in threads where the bot is mentioned.
- Capture a Slack message as a Forage item.
- Start an Investigate, Reproduce, or Fix Flight from a Grafana alert thread.
- Preview public Hive links inside Slack.
- Notify a channel about new specs, comments, and review requests.
- Mention the correct person after they link their Slack and Hive
  profiles.

Language-model replies require a configured
[Hive inference profile](./inference#agentic-workflows). Capture,
notifications, profile linking, and public link previews do not.

## Before you begin

You need:

- A Hive instance reachable through a public secure web address.
- A Hive administrator account.
- Permission to create a Slack app.
- A configured [Forage intake destination](/guide/using-hive/forage#submit-an-item).

## Create the Slack app

Open [Your Apps](https://api.slack.com/apps), select **Create New App →
From an app manifest**, choose JavaScript Object Notation
([JSON](https://www.json.org/json-en.html)), and paste the manifest below.
Replace every `<your-host>` value with the Hive domain name without the
scheme, for example `hive.example.com`.

```json
{
  "display_information": {
    "name": "Hive",
    "description": "Capture product feedback and reply to Hive mentions from Slack.",
    "background_color": "#0F172A"
  },
  "features": {
    "bot_user": {
      "display_name": "Hive",
      "always_online": false
    },
    "shortcuts": [
      {
        "name": "Capture as forage item",
        "type": "message",
        "callback_id": "capture_forage_item",
        "description": "Send this Slack message to Hive as a forage item."
      }
    ]
  },
  "oauth_config": {
    "redirect_urls": [
      "https://<your-host>/slack/install/callback",
      "https://<your-host>/account/slack/callback"
    ],
    "scopes": {
      "bot": [
        "app_mentions:read",
        "channels:history",
        "channels:read",
        "chat:write",
        "chat:write.public",
        "commands",
        "groups:history",
        "groups:read",
        "im:history",
        "im:read",
        "links:read",
        "links:write",
        "mpim:history",
        "mpim:read",
        "users:read",
        "users:read.email"
      ],
      "user": [
        "openid",
        "profile",
        "email"
      ]
    }
  },
  "settings": {
    "event_subscriptions": {
      "request_url": "https://<your-host>/api/slack/events",
      "bot_events": [
        "app_mention",
        "link_shared",
        "message.channels",
        "message.groups",
        "message.im",
        "message.mpim"
      ]
    },
    "app_unfurl_domains": [
      "<your-host>"
    ],
    "interactivity": {
      "is_enabled": true,
      "request_url": "https://<your-host>/api/slack/interactions"
    },
    "org_deploy_enabled": false,
    "socket_mode_enabled": false,
    "token_rotation_enabled": false
  }
}
```

Create the app in a development workspace. If workspaces outside that
workspace should be able to install Hive, enable **Public Distribution**
under **Manage Distribution**. Publishing in the Slack App Directory is
not required.

## Configure Hive

Copy the client identifier, client secret, and signing secret from the
Slack app's **Basic Information** page. Store them in the Hive deployment
secret as:

- [`HIVE_SLACK_CLIENT_ID`](/reference/configuration#hive_slack_client_id)
- [`HIVE_SLACK_CLIENT_SECRET`](/reference/configuration#hive_slack_client_secret)
- [`HIVE_SLACK_SIGNING_SECRET`](/reference/configuration#hive_slack_signing_secret)

Restart Hive after adding the values. The Slack installation action stays
hidden when any required value is missing.

Optionally set
[`HIVE_SLACK_ALLOWED_TEAM_IDS`](/reference/configuration#hive_slack_allowed_team_ids)
to a comma-separated list of workspace identifiers. Hive then rejects
installation and profile linking from other workspaces.

## Install a workspace

1. Sign in to Hive as an administrator.
2. Open **Ops (Operations) → Slack**.
3. Select **Connect a Slack workspace** and approve the Slack prompt.
4. Confirm that the workspace appears in Hive.

Use **Disconnect** when Hive should no longer access a workspace. Existing
audit history remains available.

## Capture a Slack message

In Slack, open a message's shortcuts and select **Capture as forage
item**. The Slack user must have signed in to Hive before capture, either
with a matching email address or through an explicitly linked profile.

The item follows the destination configured under
**Ops (Operations) → Forage**. It either becomes a Hive-managed item or a
GitHub issue in the selected repository.

When a linked user mentions the Hive bot and asks it to capture work, the
bot can use the same destination. If the destination is GitHub, Hive can
apply matching labels from that repository. Before creating the item, the
bot removes names, contact details, account and workspace identifiers,
private links, and details about who requested or is affected by the work.
The captured item retains only the technical context and generalized impact
needed to act on it.

When Hive cannot resolve the Slack user to an account, the bot replies with
a direct **Connect your Slack profile** link instead of attempting the
capture. People who are not signed in are taken through login first, then
profile connection resumes automatically.

## Link a Slack profile

After an administrator connects the workspace, signed-in users can open
`/account/identities` and select **Connect Slack profile**.

An explicit link is useful when the person's Slack and Hive email
addresses differ. Hive uses the link for captures, replies, and targeted
notifications.

## Start a Flight from a Grafana alert

Reply in a Grafana alert thread and mention Hive with one of these commands:

```text
@Hive investigate this
@Hive reproduce this
@Hive fix this
```

Hive uses the original Grafana link or a Hive Forage link in the thread to find
the alert. The person issuing the command must link their Slack profile to an
organization-member Hive account. If the alert's project has more than one
repository, include the full repository name, such as
`@Hive reproduce this in tuist/hive`.

Hive posts one progress message in the thread and updates it when the Flight is
queued, running, completed, or failed. Repeating a command while a Flight is
active returns the existing Flight instead of starting another agent session.

## Preview Hive links

Pasting a public Hive link into a connected Slack channel shows a preview
with the resource title, context, and a link back to Hive.

Preview visibility follows the anonymous dashboard view. Private specs,
private domains, organization-only Forage items, account pages, and
administrator pages do not expose their content in Slack.

## Configure notifications

Open a connected workspace under **Ops (Operations) → Slack** and edit its
notification routes. Each route connects a Hive resource type with one
Slack channel.

The Specs route can notify the channel when:

- A spec is created.
- A comment is added.
- An organization member asks for review.

Use the Slack channel identifier rather than its display name. The Hive
bot must be able to post in the selected channel.

## Troubleshooting

- If installation is unavailable, confirm that all three required Hive
  settings are present and restart the deployment.
- If Slack rejects an address, confirm that Hive is publicly reachable
  through a valid secure certificate.
- If captures fail for one person, ask them to sign in to Hive and link
  their Slack profile.
- If notifications do not arrive, confirm that the bot can access the
  configured channel.

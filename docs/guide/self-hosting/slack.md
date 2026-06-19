## Slack

Hive can be installed into one or more Slack workspaces. With Public
Distribution enabled on the Slack app, any workspace can install Hive
through the OAuth v2 flow without going through the Slack App Directory
(which would require a multi-week review).

Once a workspace is installed, Hive can:

- Reply in threads where the bot is `@`-mentioned, using the configured
  LLM.
- Capture any Slack message as a Hive feature request via a message
  shortcut (right-click a message, "More message shortcuts", pick the
  shortcut).
- Unfurl Hive links inline. When a workspace member pastes a link to a
  spec, domain, or forage item, Slack expands the message with a
  preview of the resource. Only resources that an anonymous visitor
  could see on the dashboard are previewed; private specs and
  organization-only forage items stay opaque.
- Notify a configured channel when product activity happens, starting
  with new specs and new spec comments.
- Let signed-in Hive users connect their Slack profile so Hive can
  target user-specific notifications even when Slack and Hive emails do
  not match.
- Record Slack installs, disconnects, app mentions, and captured feature
  requests in the audit trail.

## Environment variables

Set these on the Hive deployment:

- `HIVE_SLACK_CLIENT_ID`: the Slack app's client ID.
- `HIVE_SLACK_CLIENT_SECRET`: the Slack app's client secret.
- `HIVE_SLACK_SIGNING_SECRET`: the Slack app's signing secret (used to
  verify Events and Interactivity requests).
- `HIVE_SLACK_BOT_SCOPES`: optional, comma-separated list of bot OAuth
  scopes to request at install time. Defaults to:
  `app_mentions:read,channels:history,channels:read,chat:write,chat:write.public,commands,groups:history,groups:read,im:history,im:read,links:read,links:write,mpim:history,mpim:read,users:read,users:read.email`.
When any of the three required variables is missing, the integration
stays dormant: the `/slack/install` link is hidden and `/ops/slack`
shows an inert state.

## Setting up the Slack app

The fastest path is to create the app from a manifest. Go to
<https://api.slack.com/apps>, select **Create New App → From an app
manifest**, choose JSON, replace `<your-host>` with your Hive host, and
paste:

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
        "name": "Capture as feature request",
        "type": "message",
        "callback_id": "capture_feature_request",
        "description": "Send this Slack message to Hive as a feature request."
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

To configure it manually instead:

1. Go to <https://api.slack.com/apps> and **Create New App → From scratch**.
   Pick any name and workspace; you can change it later.
2. In **Basic Information**, copy the Client ID, Client Secret, and
   Signing Secret into the environment variables above.
3. In **OAuth & Permissions**:
   - Add the bot scopes listed under `HIVE_SLACK_BOT_SCOPES`.
   - Add the redirect URLs: `https://<your-host>/slack/install/callback`
     and `https://<your-host>/account/slack/callback`.
   - Add the user scopes `openid`, `profile`, and `email` for Slack
     profile linking.
4. In **Event Subscriptions**:
   - Enable events.
   - Request URL: `https://<your-host>/api/slack/events`. Slack verifies
     the URL once with a challenge; Hive responds automatically.
   - Subscribe to bot events: `app_mention`, `link_shared`,
     `message.channels`, `message.groups`, `message.im`, `message.mpim`.
   - Under **App unfurl domains**, add `<your-host>` so Slack delivers
     `link_shared` events for Hive links.
5. In **Interactivity & Shortcuts**:
   - Turn on Interactivity.
   - Request URL: `https://<your-host>/api/slack/interactions`.
   - Add a **message shortcut** with name "Capture as feature request"
     and callback ID `capture_feature_request`.
6. In **Manage Distribution**:
   - **Activate Public Distribution**. This lets any workspace install
     Hive via the install link without an App Directory submission.

## Installing into a workspace

Once `HIVE_SLACK_*` variables are set and the deploy is rolled out:

1. Sign in to Hive as an instance admin and open **Ops → Slack** at
   `/ops/slack`.
2. Click **Connect a Slack workspace**, complete the Slack OAuth prompt,
   and pick the workspace.
3. The workspace appears in the list. Click **Disconnect** to revoke
   Hive's access to that workspace (Hive keeps the row so the install
   history stays in the audit trail).
4. To post product activity into Slack, enter a notification channel ID
   on the workspace row and choose which events Hive should post.

## Linking a Slack profile

After an admin connects the workspace, signed-in users can open
`/account/identities` and click **Connect Slack profile**. Hive sends
the user through Slack's OpenID Connect flow and stores the returned
Slack workspace and user IDs on the matching workspace install. This
explicit link is used even when the user's Slack email differs from
their Hive email.

## What gets captured

The `capture_feature_request` shortcut matches the invoking Slack user
to a Hive user by email. The Slack user must have signed in to Hive at
least once (so the email is known); otherwise the shortcut responds
with an ephemeral error and nothing is captured.

Successful captures land in the unified Forage queue at `/forage` and
are recorded in the audit trail as `slack.feature_request.captured`.
Installs and disconnects are recorded too.

## Link unfurling

When the Slack app registers your Hive host as an **app unfurl domain**,
Slack delivers a `link_shared` event for every Hive URL pasted in a
connected channel. Hive looks each URL up, builds a preview, and posts
the preview back via `chat.unfurl`. Supported surfaces:

- `/specs/:number`: title, summary or first body line, and status.
- `/domains/:id`: name and description.
- `/forage/items/:origin/:id`: title, description excerpt, type, and
  status. Manual items, GitHub issues, and Grafana alerts all unfurl
  through the same surface.

Only public resources are unfurled. Anything that requires a session
to view on the dashboard stays opaque, and Slack shows the bare link.

## Notifications

Hive can post product activity to one Slack channel per connected
workspace. The first supported events are:

- `spec.created`: a new spec was created from the dashboard or MCP.
- `spec.comment.created`: a new comment was added to a spec.

The channel must be reachable by Hive's installed bot. Use the Slack
channel ID, not the display name. Instance admins configure the channel
from `/ops/slack`; no redeploy is required.

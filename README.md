<p align="center">
  <img src="priv/static/images/logo.webp" alt="Hive" width="80" />
</p>
<h1 align="center">Hive</h1>

An open-source, self-hostable platform for autonomous coding agents, inspired by [Stripe's Minions](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents-part-2) and built with Elixir and Phoenix.

Hive collects **signals** (support messages, bug reports, feature requests) from sources like Slack and GitHub. You define **swarms**, workflows that mix deterministic steps (linting, CI) with agentic steps (code generation, test fixing). When a signal arrives, Hive launches a **flight**, an execution of a swarm that turns the signal into a ready-to-review pull request with no human interaction in between. A flight produces **drops**, the individual deliverables (a PR, a reply, a report). A human then **tastes** each drop, reviewing, approving, or rejecting it before it ships.

## 🤔 Why Hive

Every tool in the software delivery chain is adding its own agentic capabilities, but those capabilities are siloed. Software delivery spans domains and services, so we needed a control plane that can oversee the whole system. Hive is that control plane: a single place to define, run, and review autonomous workflows that cut across your entire stack.

## ✨ Features

- 📡 **Signals** - Monitor Slack channels, GitHub issues, and other sources for actionable messages
- 🐝 **Swarms** - Define reusable workflows that mix deterministic and agent-driven steps
- 🚀 **Flights** - Each signal triggers a flight that autonomously works through a swarm's steps
- 🍯 **Drops** - The deliverables a flight produces: pull requests, replies, reports
- 👅 **Tasting** - Every drop goes through human review before shipping
- 🏠 **Self-hostable** - Deploy it on your own infrastructure

## 🚀 Getting started

### Prerequisites

- [mise](https://mise.jdx.dev/) for managing Erlang and Elixir versions
- [PostgreSQL](https://www.postgresql.org/) running locally

### Setup

```bash
# Install Erlang and Elixir through mise
mise install

# Install dependencies and set up the database
mix setup

# Start the server
mix phx.server
```

Then visit [localhost:3030](http://localhost:3030) in your browser.

You can also run the server inside IEx for interactive debugging:

```bash
iex -S mix phx.server
```

## 🏠 Self-hosting

Hive is designed to be self-hosted. You can deploy it using [Kamal](https://kamal-deploy.org/) or any Docker-based deployment tool. The included `Dockerfile` builds a production-ready Elixir release.

The service exposes a `GET /up` health check endpoint that returns `200 OK` when the application is running. Kamal's proxy uses this by default to verify deployments.

### Environment variables

| Variable | Description | Required |
|---|---|---|
| `SECRET_KEY_BASE` | A secret key for signing and encrypting session data. Generate one with `mix phx.gen.secret`. | Yes |
| `DATABASE_URL` | PostgreSQL connection string, e.g. `ecto://user:pass@host/hive_prod` | Yes |
| `ENCRYPTION_KEY` | A base64-encoded 256-bit key for encrypting sensitive data at rest (tokens, secrets, private keys). Generate one with `elixir -e "IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))"`. | Yes |
| `PHX_HOST` | The hostname where Hive is served, e.g. `hive.example.com` | Yes |
| `PORT` | The port the server listens on (default: `4000`) | No |
| `PHX_SERVER` | Set to `true` to start the web server (set automatically in the Docker release) | No |
| `HIVE_PUBLIC` | Set to `true` to make the instance publicly accessible without login. Guests can browse signals and swarms but cannot modify settings. | No |

#### Public instances

By default, Hive requires authentication to access any page. When `HIVE_PUBLIC=true`, public domain objects like signals and swarms become readable by anyone without logging in. A "Log in" button appears in the header for users who want to authenticate. Instance configuration and all write operations remain restricted to authenticated users. This is useful for running a public-facing Hive instance where the community can follow along.

Authorization is handled by [LetMe](https://hex.pm/packages/let_me). The policy (`Hive.Policy`) is defined in terms of Hive domain objects instead of UI areas. Public reads are granted on objects like `:signal` and `:swarm`, while configuration objects like `:instance`, `:slack_integration`, and `:github_app` require an authenticated user.

#### Identity providers

Hive uses [Ueberauth](https://github.com/ueberauth/ueberauth) for authentication. Identity providers are configured through environment variables. If no provider is configured, the login page will display an informational message.

**Google OAuth2**

To enable Google as an identity provider, set the following environment variables:

| Variable | Description |
|---|---|
| `GOOGLE_CLIENT_ID` | OAuth2 client ID from the [Google Cloud Console](https://console.cloud.google.com/apis/credentials) |
| `GOOGLE_CLIENT_SECRET` | OAuth2 client secret from the Google Cloud Console |

When creating the OAuth2 credentials in Google Cloud Console, set the authorized redirect URI to `https://<your-host>/auth/google/callback`.

> [!NOTE]
> Contributions adding support for more identity providers (GitHub, GitLab, SAML, etc.) are very welcome!

### Slack integration

Hive monitors Slack channels for messages and turns them into signals. To set this up, you need to create a Slack app and configure it to send events to your Hive instance.

#### 1. Create a Slack app from the manifest

Go to [api.slack.com/apps](https://api.slack.com/apps) and click **Create New App** > **From a manifest**. Select your workspace, then paste the following manifest (replace `YOUR_HIVE_HOST` with your actual hostname):

```json
{
  "display_information": {
    "name": "Hive",
    "description": "Monitors channels and creates signals for the Hive platform",
    "background_color": "#094a9e"
  },
  "features": {
    "bot_user": {
      "display_name": "Hive",
      "always_online": true
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "channels:history",
        "channels:read",
        "groups:history",
        "groups:read"
      ]
    }
  },
  "settings": {
    "event_subscriptions": {
      "request_url": "https://YOUR_HIVE_HOST/api/slack/events",
      "bot_events": [
        "message.channels",
        "message.groups"
      ]
    },
    "org_deploy_enabled": false,
    "socket_mode_enabled": false
  }
}
```

#### 2. Install the app and collect credentials

1. Click **Install to Workspace** and authorize the app
2. Copy the **Bot User OAuth Token** (`xoxb-...`) from **OAuth & Permissions**
3. Copy the **Signing Secret** from **Basic Information** > **App Credentials**

#### 3. Configure in Hive

1. Go to **Settings** > **Signal Sources** and add a new Slack bot
2. Enter a name, the bot token, and the signing secret
3. Add the channels you want to monitor (you'll need the channel IDs, which you can find by right-clicking a channel in Slack > **View channel details** > the ID is at the bottom)

#### 4. Invite the bot

Invite the bot to each channel you want to monitor by typing `/invite @Hive` in the channel.

### GitHub integration

Hive monitors GitHub repositories for new issues and turns them into signals. Comments on tracked issues are added as signal messages. To set this up, you need to create a GitHub App and configure its webhook.

#### 1. Create a GitHub App

Go to **Settings** > **Developer settings** > **GitHub Apps** > **New GitHub App** and configure it:

- **GitHub App name**: Hive (or any name you prefer)
- **Homepage URL**: `https://YOUR_HIVE_HOST`
- **Webhook URL**: `https://YOUR_HIVE_HOST/api/github/events`
- **Webhook secret**: Generate a random secret (e.g. `openssl rand -hex 32`)
- **Permissions**:
  - **Repository permissions** > **Issues**: Read-only
- **Subscribe to events**: Check **Issues** and **Issue comment**

#### 2. Generate a private key

In your GitHub App settings, scroll to **Private keys** and click **Generate a private key**. This downloads a `.pem` file that Hive uses to authenticate API requests.

#### 3. Install the app

Click **Install App** in the sidebar and install it on the repositories you want to monitor. Note the **installation ID** from the URL (e.g. `https://github.com/settings/installations/12345678` means the ID is `12345678`).

#### 4. Configure in Hive

1. Go to **Settings** > **Signal Sources** and add a new GitHub App
2. Enter the name, App ID (from the app's General page), installation ID, private key (paste the full PEM contents), and webhook secret
3. Add the repositories you want to monitor (enter the owner and repository name separately, e.g. owner: `tuist`, repository: `tuist`)

## 📄 License

[MPL-2.0](LICENSE.md)

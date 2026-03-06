<p align="center">
  <img src="priv/static/images/logo.webp" alt="Hive" width="80" />
</p>
<h1 align="center">Hive</h1>

An open-source, self-hostable platform for autonomous coding agents, inspired by [Stripe's Minions](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents-part-2) and built with Elixir and Phoenix.

Hive collects **signals** (support messages, bug reports, feature requests) from sources like Slack and GitHub, then dispatches **swarms** of autonomous agents to act on them. A swarm combines deterministic steps (linting, CI) with flexible agent loops (code generation, test fixing) to turn a signal into a ready-to-review pull request with no human interaction in between.

## ✨ Features

- 📡 **Signal collection** - Monitor Slack channels, GitHub issues, and other sources for actionable messages
- 🐝 **Swarm orchestration** - Define workflows that mix deterministic and agent-driven steps
- 🤖 **Autonomous agents** - From signal to pull request with no back-and-forth
- 👀 **Human review** - Every output goes through a human before merging
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

### Environment variables

| Variable | Description | Required |
|---|---|---|
| `SECRET_KEY_BASE` | A secret key for signing and encrypting session data. Generate one with `mix phx.gen.secret`. | Yes |
| `DATABASE_URL` | PostgreSQL connection string, e.g. `ecto://user:pass@host/hive_prod` | Yes |
| `PHX_HOST` | The hostname where Hive is served, e.g. `hive.example.com` | Yes |
| `PORT` | The port the server listens on (default: `4000`) | No |
| `PHX_SERVER` | Set to `true` to start the web server (set automatically in the Docker release) | No |

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

## 📄 License

[MPL-2.0](LICENSE.md)

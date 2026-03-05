<p align="center">
  <img src="priv/static/images/logo.webp" alt="Hive" width="80" />
</p>
<h1 align="center">Hive</h1>

An open-source, self-hostable take on [Stripe's Minions](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents-part-2) system, built with Elixir and Phoenix.

Stripe's Minions are autonomous coding agents that turn a task description into a ready-to-review pull request with no human interaction in between. They use **blueprints**, hybrid orchestration flows that combine deterministic steps (linting, CI) with flexible agent loops (code generation, test fixing), to keep LLMs contained in predictable boxes. A typical minion run starts from a message, gathers context from tickets, docs, and code search, writes the code, runs tests, and opens a PR for human review.

Hive brings that same idea into the open. Define blueprints, point them at your repos, and let autonomous agents do the grunt work while you stay in the review seat.

## ✨ Features

- 🔧 **Blueprint orchestration** - Define hybrid workflows mixing deterministic and agent-driven steps
- 🔍 **Context gathering** - Pull in relevant docs, tickets, and code before the agent starts
- 🤖 **One-shot agents** - From task to pull request with no back-and-forth
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

Then visit [localhost:4000](http://localhost:4000) in your browser.

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

## 📄 License

[MPL-2.0](LICENSE.md)

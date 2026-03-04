# 🐝 Hive

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

## 📄 License

[MPL-2.0](LICENSE.md)

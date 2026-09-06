<p align="center">
  <img src="priv/static/images/logo.png" alt="Hive" width="20%" />
</p>

<h1 align="center">Hive</h1>

> [!WARNING]
> Hive is a work in progress and is still changing quickly. Expect APIs,
> behavior, and deployment details to change often.

<p align="center">
  <a href="https://github.com/tuist/hive/actions/workflows/hive.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/tuist/hive/hive.yml?branch=main&label=ci&style=flat-square" alt="CI" />
  </a>
  <a href="https://github.com/tuist/hive/actions/workflows/deploy.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/tuist/hive/deploy.yml?branch=main&label=deploy&style=flat-square" alt="Deployment" />
  </a>
  <a href="https://github.com/tuist/hive/actions/workflows/docs.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/tuist/hive/docs.yml?branch=main&label=docs&style=flat-square" alt="Docs" />
  </a>
  <a href="https://github.com/tuist/hive/releases">
    <img src="https://img.shields.io/github/v/release/tuist/hive?label=release&style=flat-square" alt="Latest release" />
  </a>
  <a href="LICENSE.md">
    <img src="https://img.shields.io/github/license/tuist/hive?style=flat-square" alt="MPL-2.0 license" />
  </a>
</p>

At Tuist we've reimagined how we shape and build product by leaning into
LLMs and agentic workflows, and Hive is our take on it. It's built to run
inside our own team and equally to be opened up to the people who use
your products.

When an LLM is configured, Hive can continuously evolve its domains from
new forage items and specs, keeping the taxonomy aligned with durable
Tuist business domains instead of one-off tickets or vague buckets.

Hive can also connect Slack workspaces. Instance admins manage workspace
installs, and signed-in users can turn Slack messages into forage items
or receive bot replies in Slack threads.

Hive also has native applications for carrying work from intent to execution.
The macOS application hosts local projects and agent sessions. The iPhone and
Apple Watch applications surface remote sessions from Hive and from nearby Macs
running Hive on the same network. The existing server-backed Forage,
specification, drop, and account surfaces remain available from the iPhone
application.

Native product state and execution capabilities live behind focused Rust
modules. Each platform links only the capabilities it uses, keeping mobile
applications independent from desktop-only project and agent machinery. See
[`native/README.md`](native/README.md) for the architecture and build commands.

Hive is licensed under [MPL-2.0](LICENSE.md). We don't offer it as a
managed service, but you can try our own instance, or self-host your own.

## Our instance

Tuist runs the canonical Hive instance at
[hive.tuist.dev](https://hive.tuist.dev). It is the easiest way to see
Hive in action and to follow along with how we shape product work at
Tuist.

## Documentation

Read the documentation at
[docs.hive.tuist.dev](https://docs.hive.tuist.dev) to learn more about
how Hive works and how to self-host it.

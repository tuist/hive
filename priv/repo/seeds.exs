# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias Hive.Repo
alias Hive.Accounts.User
alias Hive.Integrations.SlackIntegration
alias Hive.Integrations.SlackChannel
alias Hive.Signals.Signal

# Create a seeded test user for development
case Repo.get_by(User, email: "test@hive.dev") do
  nil ->
    %User{}
    |> User.changeset(%{
      email: "test@hive.dev",
      name: "Test User"
    })
    |> Repo.insert!()

  _user ->
    :ok
end

# Create Slack bots with monitored channels
bots = [
  %{
    name: "Community Support",
    bot_token: "xoxb-community-support-fake",
    channels: [
      %{channel_id: "C001SUPPORT", channel_name: "support"},
      %{channel_id: "C002GENERAL", channel_name: "general"},
      %{channel_id: "C003FEEDBACK", channel_name: "product-feedback"}
    ]
  },
  %{
    name: "Internal Team",
    bot_token: "xoxb-internal-team-fake",
    channels: [
      %{channel_id: "C010ONCALL", channel_name: "on-call"},
      %{channel_id: "C011INCIDENTS", channel_name: "incidents"}
    ]
  }
]

for bot_attrs <- bots do
  {channels, bot_attrs} = Map.pop(bot_attrs, :channels)

  integration =
    case Repo.get_by(SlackIntegration, name: bot_attrs.name) do
      nil ->
        %SlackIntegration{}
        |> SlackIntegration.changeset(bot_attrs)
        |> Repo.insert!()

      existing ->
        existing
    end

  for channel_attrs <- channels do
    case Repo.get_by(SlackChannel,
           channel_id: channel_attrs.channel_id,
           slack_integration_id: integration.id
         ) do
      nil ->
        %SlackChannel{}
        |> SlackChannel.changeset(Map.put(channel_attrs, :slack_integration_id, integration.id))
        |> Repo.insert!()

      _existing ->
        :ok
    end
  end
end

# Seed some signals from Slack
signals = [
  %{
    title: "Getting error when running tuist generate",
    body:
      "Hey team, I'm getting a weird error when running `tuist generate` on the latest version. It says something about a missing manifest. Anyone seen this before?",
    source: "slack",
    source_author: "alice",
    source_channel: "#support",
    source_url: "https://tuist-community.slack.com/archives/C001SUPPORT/p1709654400000100",
    source_timestamp: ~U[2026-03-04 10:00:00Z]
  },
  %{
    title: "Cache misses after upgrading to 4.x",
    body:
      "We upgraded from 3.x to 4.x and now we're seeing a lot of cache misses. Our build times went from 2 minutes to 15 minutes. Is there a migration guide for the cache format?",
    source: "slack",
    source_author: "bob",
    source_channel: "#support",
    source_url: "https://tuist-community.slack.com/archives/C001SUPPORT/p1709654400000200",
    source_timestamp: ~U[2026-03-04 11:30:00Z]
  },
  %{
    title: "Feature request: better monorepo support",
    body:
      "Would love to see better monorepo support with independent versioning per package. Right now we have to work around some limitations with our setup of 50+ modules.",
    source: "slack",
    source_author: "carol",
    source_channel: "#product-feedback",
    source_url: "https://tuist-community.slack.com/archives/C003FEEDBACK/p1709654400000300",
    source_timestamp: ~U[2026-03-04 14:00:00Z]
  },
  %{
    title: "Love the new dashboard UI",
    body:
      "Just wanted to say the new Tuist Cloud dashboard looks amazing. The build insights are super helpful for our team. Great work!",
    source: "slack",
    source_author: "dave",
    source_channel: "#general",
    source_url: "https://tuist-community.slack.com/archives/C002GENERAL/p1709654400000400",
    source_timestamp: ~U[2026-03-04 15:45:00Z]
  },
  %{
    title: "Binary caching not working with SPM dependencies",
    body:
      "When I have SPM dependencies in my project, binary caching seems to skip them entirely. Is this expected behavior or a bug?",
    source: "slack",
    source_author: "eve",
    source_channel: "#support",
    source_url: "https://tuist-community.slack.com/archives/C001SUPPORT/p1709654400000500",
    source_timestamp: ~U[2026-03-05 09:15:00Z]
  },
  %{
    title: "How to set up CI with Tuist Cloud?",
    body:
      "We're trying to integrate Tuist Cloud into our GitHub Actions CI pipeline. The docs mention a token but I'm not sure where to generate it. Can someone point me in the right direction?",
    source: "slack",
    source_author: "frank",
    source_channel: "#support",
    source_url: "https://tuist-community.slack.com/archives/C001SUPPORT/p1709654400000600",
    source_timestamp: ~U[2026-03-05 10:30:00Z]
  },
  %{
    title: "Production incident: API latency spike",
    body:
      "We are seeing elevated API latency in production. P99 went from 200ms to 2s. Investigating now.",
    source: "slack",
    source_author: "ops-bot",
    source_channel: "#incidents",
    source_url: "https://tuist-hq.slack.com/archives/C011INCIDENTS/p1709654400000700",
    source_timestamp: ~U[2026-03-05 14:00:00Z]
  }
]

for signal_attrs <- signals do
  # Use source_url as a unique identifier to avoid duplicates
  case Repo.get_by(Signal, source_url: signal_attrs.source_url) do
    nil ->
      %Signal{}
      |> Signal.changeset(signal_attrs)
      |> Repo.insert!()

    _existing ->
      :ok
  end
end

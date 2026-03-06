# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias Hive.Repo
alias Hive.Accounts.User
alias Hive.Integrations.SlackIntegration
alias Hive.Integrations.SlackChannel
alias Hive.Integrations.GitHubApp
alias Hive.Integrations.GitHubRepository
alias Hive.Signals.Signal
alias Hive.Signals.SignalMessage

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

# Create GitHub apps with monitored repositories
github_apps = [
  %{
    name: "Hive GitHub App",
    webhook_secret: "whsec_fake_dev_secret",
    app_id: "123456",
    private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake-dev-key\n-----END RSA PRIVATE KEY-----",
    installation_id: "98765",
    repositories: [
      %{owner: "tuist", repo: "tuist"},
      %{owner: "tuist", repo: "hive"}
    ]
  }
]

for app_attrs <- github_apps do
  {repositories, app_attrs} = Map.pop(app_attrs, :repositories)

  app =
    case Repo.get_by(GitHubApp, name: app_attrs.name) do
      nil ->
        %GitHubApp{}
        |> GitHubApp.changeset(app_attrs)
        |> Repo.insert!()

      existing ->
        existing
    end

  for repo_attrs <- repositories do
    case Repo.get_by(GitHubRepository,
           owner: repo_attrs.owner,
           repo: repo_attrs.repo,
           github_app_id: app.id
         ) do
      nil ->
        %GitHubRepository{}
        |> GitHubRepository.changeset(Map.put(repo_attrs, :github_app_id, app.id))
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
  },
  %{
    title: "Swift 6 strict concurrency breaks generated project",
    body:
      "When enabling strict concurrency checking in Swift 6, the generated Xcode project has several warnings that become errors. The generated `TuistBundle` accessor isn't marked as `@Sendable`.",
    source: "github",
    source_author: "swiftdev42",
    source_channel: "tuist/tuist",
    source_url: "https://github.com/tuist/tuist/issues/7001",
    source_timestamp: ~U[2026-03-05 16:00:00Z]
  },
  %{
    title: "Add support for visionOS destinations",
    body:
      "It would be great to have first-class support for visionOS as a deployment destination. Currently we have to use workarounds with custom settings to target visionOS.",
    source: "github",
    source_author: "visionpro_fan",
    source_channel: "tuist/tuist",
    source_url: "https://github.com/tuist/tuist/issues/7002",
    source_timestamp: ~U[2026-03-06 08:30:00Z]
  }
]

inserted_signals =
  for signal_attrs <- signals do
    case Repo.get_by(Signal, source_url: signal_attrs.source_url) do
      nil ->
        %Signal{}
        |> Signal.changeset(signal_attrs)
        |> Repo.insert!()

      existing ->
        existing
    end
  end

# Seed conversation threads for some signals
conversations = %{
  "Getting error when running tuist generate" => [
    %{
      author: "bob",
      body:
        "I had the same issue. Try deleting the .build folder and running `tuist clean` first.",
      source_timestamp: ~U[2026-03-04 10:15:00Z]
    },
    %{
      author: "alice",
      body: "That worked! Looks like there was a stale cache from a previous version. Thanks!",
      source_timestamp: ~U[2026-03-04 10:22:00Z]
    },
    %{
      author: "carol",
      body:
        "We should probably add this to the troubleshooting docs. I've seen this come up a few times.",
      source_timestamp: ~U[2026-03-04 10:30:00Z]
    }
  ],
  "Cache misses after upgrading to 4.x" => [
    %{
      author: "eve",
      body:
        "Same here. The cache key format changed in 4.x so all existing caches are invalidated.",
      source_timestamp: ~U[2026-03-04 11:45:00Z]
    },
    %{
      author: "frank",
      body:
        "Is there a way to migrate the old cache? Rebuilding everything from scratch takes forever for us.",
      source_timestamp: ~U[2026-03-04 12:00:00Z]
    },
    %{
      author: "bob",
      body:
        "No migration path unfortunately. But once the new cache warms up, times should be even better than 3.x.",
      source_timestamp: ~U[2026-03-04 12:10:00Z]
    }
  ],
  "Swift 6 strict concurrency breaks generated project" => [
    %{
      author: "tuist-maintainer",
      body:
        "Thanks for reporting! This is a known issue with the code generation templates. We need to audit all generated accessors for Sendable conformance.",
      source_timestamp: ~U[2026-03-05 16:30:00Z]
    },
    %{
      author: "swiftdev42",
      body: "Happy to help with a PR if you can point me to the relevant templates.",
      source_timestamp: ~U[2026-03-05 17:00:00Z]
    }
  ],
  "Production incident: API latency spike" => [
    %{
      author: "ops-bot",
      body:
        "Update: traced the issue to a slow database query on the projects endpoint. Rolling out a fix now.",
      source_timestamp: ~U[2026-03-05 14:20:00Z]
    },
    %{
      author: "ops-bot",
      body:
        "Fix deployed. P99 latency back to normal at 180ms. Root cause was a missing index on the new analytics table.",
      source_timestamp: ~U[2026-03-05 14:45:00Z]
    }
  ]
}

for signal <- inserted_signals,
    messages = Map.get(conversations, signal.title, []),
    message_attrs <- messages do
  case Repo.get_by(SignalMessage, signal_id: signal.id, body: message_attrs.body) do
    nil ->
      %SignalMessage{}
      |> SignalMessage.changeset(Map.put(message_attrs, :signal_id, signal.id))
      |> Repo.insert!()

    _existing ->
      :ok
  end
end

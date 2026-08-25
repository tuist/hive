import Config

noora_static_path = Path.expand("../deps/noora/priv/static", __DIR__)

config :hive,
  ecto_repos: [Hive.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id_type: :binary_id]

config :hive, HiveWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HiveWeb.ErrorHTML, json: HiveWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Hive.PubSub,
  live_view: [signing_salt: "kY3hN2pQ"]

config :esbuild,
  version: "0.25.4",
  hive: [
    args: [
      "js/app.js",
      "--bundle",
      "--target=es2022",
      "--outdir=../priv/static/assets/js",
      "--alias:noora/noora.css=#{noora_static_path}/noora.css"
    ],
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :mime, :types, %{
  "text/event-stream" => ["event-stream"]
}

config :tzdata, http_client: Hive.TzdataHTTPClient

config :flop, repo: Hive.Repo

config :mdex_native, syntax_highlighter: :lumis

# Every agent LLM call runs through ReqLLM's own `ReqLLM.Finch` pool, which
# defaults to just 8 connections (size 1 x count 8) per host. A slow model plus
# ReqLLM/Oban retries can starve that pool ("Finch was unable to provide a
# connection"), stalling agent work. The `:agents` Oban queue caps real
# concurrency low, so extra pool capacity costs nothing at the endpoint while
# absorbing retry and connection-teardown churn.
config :req_llm, stream_pool_count: 16

config :boruta, Boruta.Oauth,
  repo: Hive.Repo,
  contexts: [
    resource_owners: Hive.OAuth.ResourceOwners
  ],
  issuer: "http://localhost"

config :hive, Oban,
  repo: Hive.Repo,
  peer: Hive.Oban.Peers.Database,
  queues: [default: 5, agents: 2],
  plugins: [
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/30 * * * *", Hive.Domains.EvolutionWorker},
       {"@reboot", Hive.Drops.GitHubReleasesSyncer},
       {"*/15 * * * *", Hive.Drops.GitHubReleasesSyncer},
       {"@reboot", Hive.Drops.RssSyncer},
       {"*/15 * * * *", Hive.Drops.RssSyncer},
       {"@reboot", Hive.Drops.WeeklyDigestWorker},
       {"5 18 * * *", Hive.Drops.WeeklyDigestWorker},
       {"@reboot", Hive.Forage.GitHubIssueSyncer},
       {"*/15 * * * *", Hive.Forage.GitHubIssueSyncer},
       {"*/15 * * * *", Hive.Forage.GitHubIssueClassificationSweeper},
       {"*/15 * * * *", Hive.Drops.DomainClassificationSweeper},
       {"* * * * *", Hive.Notifications.DispatcherWorker}
     ]}
  ]

config :hive, :email, from: nil

config :hive, Hive.Notifications.Mailer, adapter: Swoosh.Adapters.Local

# Ueberauth's plug reads the providers list at plug-init time (which is
# compile-time in prod). Declare every possible provider here with just
# the strategy module + static options; ueberauth_oidcc looks up its
# credentials at request time from `:ueberauth_oidcc, :providers`,
# which runtime.exs populates from env vars. Without a compile-time
# entry here the strategy isn't registered and `/auth/:provider`
# fails with "could not be started".
#
# GitHub has no OIDC discovery document, so it can't go through Oidcc;
# it uses its own strategy. Its credentials live in
# `:ueberauth, Ueberauth.Strategy.Github.OAuth`, set by runtime.exs.
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Oidcc, [issuer: :google, scopes: ["openid", "profile", "email"]]},
    oidc: {Ueberauth.Strategy.Oidcc, [issuer: :oidc, scopes: ["openid", "profile", "email"]]},
    github: {Ueberauth.Strategy.Github, [default_scope: "user:email"]}
  ]

# Issuers + per-strategy credentials are populated at runtime by
# config/runtime.exs based on which env vars are set.
config :ueberauth_oidcc, :issuers, []
config :ueberauth_oidcc, :providers, []

import_config "#{config_env()}.exs"

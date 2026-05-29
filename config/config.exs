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
  pubsub_server: Hive.PubSub

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

# Ueberauth's plug reads the providers list at plug-init time (which is
# compile-time in prod). Declare every possible provider here with just
# the strategy module + static options; ueberauth_oidcc looks up its
# credentials at request time from `:ueberauth_oidcc, :providers`,
# which runtime.exs populates from env vars. Without a compile-time
# entry here the strategy isn't registered and `/auth/:provider`
# fails with "could not be started".
config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Oidcc,
       [issuer: :google, scopes: ["openid", "profile", "email"]]},
    oidc:
      {Ueberauth.Strategy.Oidcc,
       [issuer: :oidc, scopes: ["openid", "profile", "email"]]}
  ]

# Issuers + per-strategy credentials are populated at runtime by
# config/runtime.exs based on which env vars are set.
config :ueberauth_oidcc, :issuers, []
config :ueberauth_oidcc, :providers, []

import_config "#{config_env()}.exs"

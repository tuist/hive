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

# Ueberauth providers and OIDC issuers are populated at runtime from
# environment variables (see config/runtime.exs). Defaults are empty so
# nothing is started when no provider is configured.
config :ueberauth_oidcc, :issuers, []

config :ueberauth, Ueberauth, providers: []

import_config "#{config_env()}.exs"

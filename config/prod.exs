import Config

config :hive, HiveWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [paths: ["/live", "/ready"]]
  ]

config :logger, level: :info

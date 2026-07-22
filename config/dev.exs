import Config

alias Hive.Config.DevInstance

Code.require_file("dev_instance.exs", __DIR__)

config :hive, Hive.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: DevInstance.database_name("hive_dev"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :hive, HiveWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: DevInstance.port(4000)],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "E4nkXHqNgTDJksivS5dfCj6Q7X5Cq3/OdwqVf1Sr5xcJ3Xp9qAyXMyyWKzn+FZIk",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:hive, ~w(--sourcemap=inline --watch)]}
  ]

config :hive, HiveWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/hive_web/(controllers|components)/.*\.(ex|heex)$",
      ~r"lib/hive_web/router\.ex$"
    ]
  ]

config :hive, dev_routes: true

config :hive, :email, from: {"Hive", "notifications@hive.test"}

config :hive, :og_images, start_browser_pool: false

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :plug_init_mode, :runtime
config :phoenix, :stacktrace_depth, 20

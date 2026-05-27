import Config

alias Hive.Config.DevInstance

Code.require_file("dev_instance.exs", __DIR__)

config :hive, Hive.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database:
    DevInstance.database_name(
      "hive_test",
      partition: System.get_env("MIX_TEST_PARTITION")
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :hive, HiveWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: DevInstance.port(4002)],
  secret_key_base: "8PVwuyIpKT4kmnC7zb3f91MhGqLXN/FVOq1Q1gysnwrEPB4JjG2WsOcL29eGx/BF",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
config :phoenix, sort_verified_routes_query_params: true

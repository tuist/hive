import Config

alias Hive.Config.DevInstance

if config_env() != :prod do
  Code.require_file("dev_instance.exs", __DIR__)
end

if System.get_env("PHX_SERVER") do
  config :hive, HiveWeb.Endpoint, server: true
end

default_port =
  case config_env() do
    :dev -> DevInstance.port(4000)
    :test -> DevInstance.port(4002)
    _ -> 4000
  end

port =
  "PORT"
  |> System.get_env(Integer.to_string(default_port))
  |> String.to_integer()

config :hive, HiveWeb.Endpoint, http: [port: port]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :hive, Hive.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    ssl: System.get_env("DATABASE_SSL") in ~w(true 1)

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "hive.tuist.dev"

  config :hive, HiveWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    secret_key_base: secret_key_base
end

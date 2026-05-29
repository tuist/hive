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

config :hive, :auth,
  mode: System.get_env("HIVE_AUTH_MODE", "none"),
  product_name: System.get_env("HIVE_PRODUCT_NAME", "Hive"),
  product_tagline: System.get_env("HIVE_PRODUCT_TAGLINE", "Product work orchestration"),
  provider_name: System.get_env("HIVE_AUTH_PROVIDER_NAME", "Identity provider"),
  oidc_provider: System.get_env("HIVE_OIDC_PROVIDER", "generic"),
  oidc_client_id: System.get_env("HIVE_OIDC_CLIENT_ID"),
  oidc_client_secret: System.get_env("HIVE_OIDC_CLIENT_SECRET"),
  oidc_authorize_url: System.get_env("HIVE_OIDC_AUTHORIZE_URL"),
  oidc_token_url: System.get_env("HIVE_OIDC_TOKEN_URL"),
  oidc_userinfo_url: System.get_env("HIVE_OIDC_USERINFO_URL"),
  oidc_scopes: System.get_env("HIVE_OIDC_SCOPES", "openid profile email"),
  oidc_allowed_domains: System.get_env("HIVE_OIDC_ALLOWED_DOMAINS")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  database_ssl_opts =
    case System.get_env("DATABASE_SSL_CA_CERT_FILE") do
      nil -> [verify: :verify_none]
      "" -> [verify: :verify_none]
      path -> [cacertfile: path, verify: :verify_peer]
    end

  config :hive, Hive.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    ssl: System.get_env("DATABASE_SSL") in ~w(true 1),
    ssl_opts: database_ssl_opts

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

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

oauth_issuer =
  System.get_env("HIVE_OAUTH_ISSUER") ||
    case config_env() do
      :prod -> "https://#{System.get_env("PHX_HOST", "hive.tuist.dev")}"
      :test -> "http://www.example.com"
      _ -> "http://localhost:#{port}"
    end

config :boruta, Boruta.Oauth, issuer: oauth_issuer

scopes = ["openid", "profile", "email"]

present? = fn value -> is_binary(value) and String.trim(value) != "" end

parse_domains = fn
  nil ->
    []

  value when is_binary(value) ->
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))
end

parse_boolean = fn value ->
  value
  |> to_string()
  |> String.trim()
  |> String.downcase()
  |> then(&(&1 in ~w(true 1)))
end

object_storage_provider =
  "HIVE_OBJECT_STORAGE_PROVIDER"
  |> System.get_env("none")
  |> String.trim()
  |> String.downcase()
  |> case do
    "none" ->
      :none

    "" ->
      :none

    "s3" ->
      :s3

    provider ->
      raise """
      unsupported HIVE_OBJECT_STORAGE_PROVIDER=#{provider}.
      Supported values are: none, s3
      """
  end

config :hive, :object_storage,
  provider: object_storage_provider,
  s3: [
    bucket: System.get_env("HIVE_S3_BUCKET"),
    region: System.get_env("HIVE_S3_REGION", "us-east-1"),
    endpoint_url: System.get_env("HIVE_S3_ENDPOINT_URL"),
    access_key_id: System.get_env("HIVE_S3_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("HIVE_S3_SECRET_ACCESS_KEY"),
    public_base_url: System.get_env("HIVE_S3_PUBLIC_BASE_URL"),
    force_path_style: parse_boolean.(System.get_env("HIVE_S3_FORCE_PATH_STYLE"))
  ]

config :hive, :github_app,
  app_id: System.get_env("HIVE_GITHUB_APP_ID"),
  installation_id: System.get_env("HIVE_GITHUB_APP_INSTALLATION_ID"),
  private_key: System.get_env("HIVE_GITHUB_APP_PRIVATE_KEY"),
  webhook_secret: System.get_env("HIVE_GITHUB_WEBHOOK_SECRET"),
  api_url: System.get_env("HIVE_GITHUB_API_URL", "https://api.github.com")

# Slack app credentials. With Public Distribution enabled on the Slack
# app, any workspace can install Hive via /slack/install without going
# through the Slack App Directory. The signing secret is app-wide; the
# per-workspace bot token is captured during OAuth and persisted in
# `slack_installations`.
config :hive, :slack,
  client_id: System.get_env("HIVE_SLACK_CLIENT_ID"),
  client_secret: System.get_env("HIVE_SLACK_CLIENT_SECRET"),
  signing_secret: System.get_env("HIVE_SLACK_SIGNING_SECRET"),
  scopes: System.get_env("HIVE_SLACK_BOT_SCOPES"),
  allowed_team_ids: System.get_env("HIVE_SLACK_ALLOWED_TEAM_IDS")

email_provider =
  System.get_env("HIVE_EMAIL_PROVIDER", "none")
  |> String.trim()
  |> String.downcase()

email_from = System.get_env("HIVE_EMAIL_FROM")
email_message_stream = System.get_env("HIVE_EMAIL_MESSAGE_STREAM")

case email_provider do
  provider when provider in ["", "none"] ->
    :ok

  "postmark" ->
    postmark_token =
      System.get_env("HIVE_POSTMARK_SERVER_TOKEN") ||
        raise "environment variable HIVE_POSTMARK_SERVER_TOKEN is required for Postmark email"

    if not present?.(email_from) do
      raise "environment variable HIVE_EMAIL_FROM is required when email delivery is enabled"
    end

    config :hive, :email, from: email_from, message_stream: email_message_stream

    config :hive, Hive.Notifications.Mailer,
      adapter: Swoosh.Adapters.Postmark,
      api_key: postmark_token

  "smtp" ->
    relay =
      System.get_env("HIVE_SMTP_RELAY") ||
        raise "environment variable HIVE_SMTP_RELAY is required for SMTP email"

    if not present?.(email_from) do
      raise "environment variable HIVE_EMAIL_FROM is required when email delivery is enabled"
    end

    smtp_port = System.get_env("HIVE_SMTP_PORT", "587") |> String.to_integer()

    config :hive, :email, from: email_from

    smtp_username = System.get_env("HIVE_SMTP_USERNAME")
    smtp_password = System.get_env("HIVE_SMTP_PASSWORD")
    implicit_tls? = smtp_port == 465

    smtp_options = [
      adapter: Swoosh.Adapters.SMTP,
      relay: relay,
      port: smtp_port,
      auth: if(present?.(smtp_username) and present?.(smtp_password), do: :always, else: :never),
      tls: if(implicit_tls?, do: :never, else: :always),
      ssl: implicit_tls?,
      retries: 2
    ]

    smtp_options =
      if present?.(smtp_username) and present?.(smtp_password) do
        Keyword.merge(smtp_options, username: smtp_username, password: smtp_password)
      else
        smtp_options
      end

    config :hive, Hive.Notifications.Mailer, smtp_options

  provider ->
    raise "unsupported HIVE_EMAIL_PROVIDER=#{provider}. Supported values are: none, postmark, smtp"
end

if opendata_vector_url = System.get_env("HIVE_OPENDATA_VECTOR_URL") do
  config :hive, :opendata_vector, base_url: opendata_vector_url
end

if sentry_dsn = System.get_env("SENTRY_DSN") do
  sentry_report_oban_retries? =
    parse_boolean.(System.get_env("SENTRY_OBAN_REPORT_RETRIES", "false"))

  oban_integration =
    [
      capture_errors: parse_boolean.(System.get_env("SENTRY_OBAN_CAPTURE_ERRORS", "true")),
      cron: [enabled: parse_boolean.(System.get_env("SENTRY_OBAN_CRON_MONITORING", "true"))]
    ]
    |> then(fn config ->
      if sentry_report_oban_retries? do
        config
      else
        Keyword.put(
          config,
          :should_report_error_callback,
          &Hive.SentryEventFilter.report_oban_error?/2
        )
      end
    end)

  config :sentry,
    dsn: sentry_dsn,
    environment_name: System.get_env("SENTRY_ENVIRONMENT", to_string(config_env())),
    release: System.get_env("SENTRY_RELEASE") || to_string(Application.spec(:hive, :vsn)),
    enable_source_code_context: true,
    root_source_code_paths: [File.cwd!()],
    integrations: [oban: oban_integration],
    before_send: {Hive.SentryEventFilter, :before_send}
end

# Condukt-backed agents read their LLM credentials from `:hive, :llm`.
# When `HIVE_LLM_API_KEY` is unset the config stays empty and `Hive.Agents`
# refuses to run, so the rest of the app keeps booting in environments
# (CI, self-hosters without an LLM) that don't ship agentic features.
case System.get_env("HIVE_LLM_API_KEY") do
  empty when empty in [nil, ""] ->
    :ok

  api_key ->
    model =
      System.get_env("HIVE_LLM_MODEL") ||
        raise "environment variable HIVE_LLM_MODEL is required when HIVE_LLM_API_KEY is set"

    config :hive, :llm,
      api_key: api_key,
      model: model,
      base_url: System.get_env("HIVE_LLM_BASE_URL")
end

coding_runner =
  System.get_env(
    "HIVE_CODING_RUNNER",
    if(config_env() == :dev, do: "microsandbox", else: "disabled")
  )
  |> String.trim()
  |> String.downcase()

coding_sandbox_options =
  case System.get_env("HIVE_CODING_SANDBOX_OPTIONS") do
    value when is_binary(value) ->
      if present?.(value) do
        case JSON.decode(value) do
          {:ok, options} when is_map(options) ->
            options

          _other ->
            raise "environment variable HIVE_CODING_SANDBOX_OPTIONS must contain an object"
        end
      else
        %{}
      end

    _other ->
      %{}
  end

config :hive, :coding_runs,
  runner: coding_runner,
  sandbox_module: System.get_env("HIVE_CODING_SANDBOX_MODULE"),
  sandbox_options: coding_sandbox_options,
  image: System.get_env("HIVE_CODING_IMAGE", "ubuntu:24.04"),
  cpus: System.get_env("HIVE_CODING_CPUS", "2") |> String.to_integer(),
  memory: System.get_env("HIVE_CODING_MEMORY_MIB", "4096") |> String.to_integer(),
  disk: System.get_env("HIVE_CODING_DISK_MIB", "8192") |> String.to_integer(),
  timeout_minutes: System.get_env("HIVE_CODING_TIMEOUT_MINUTES", "30") |> String.to_integer(),
  setup_command: System.get_env("HIVE_CODING_SETUP_COMMAND"),
  microsandbox_home: System.get_env("HIVE_MICROSANDBOX_HOME")

inference_providers =
  case System.get_env("HIVE_INFERENCE_PROVIDERS") do
    value when is_binary(value) ->
      if present?.(value), do: JSON.decode!(value), else: %{}

    _other ->
      %{}
  end

inference_base_url = System.get_env("HIVE_INFERENCE_UPSTREAM_BASE_URL")

inference_providers =
  if present?.(inference_base_url) do
    provider_id = System.get_env("HIVE_INFERENCE_UPSTREAM_ID", "default")

    provider =
      %{
        "base_url" => inference_base_url,
        "api_key" => System.get_env("HIVE_INFERENCE_UPSTREAM_API_KEY"),
        "timeout" => System.get_env("HIVE_INFERENCE_UPSTREAM_TIMEOUT")
      }

    Map.put(inference_providers, provider_id, provider)
  else
    inference_providers
  end

if map_size(inference_providers) > 0 do
  config :hive, :inference, providers: inference_providers
end

google_client_id = System.get_env("HIVE_GOOGLE_CLIENT_ID")
google_client_secret = System.get_env("HIVE_GOOGLE_CLIENT_SECRET")
google_allowed = parse_domains.(System.get_env("HIVE_GOOGLE_ALLOWED_DOMAINS"))

oidc_issuer = System.get_env("HIVE_OIDC_ISSUER")
oidc_client_id = System.get_env("HIVE_OIDC_CLIENT_ID")
oidc_client_secret = System.get_env("HIVE_OIDC_CLIENT_SECRET")
oidc_display_name = System.get_env("HIVE_OIDC_DISPLAY_NAME", "Identity provider")
oidc_allowed = parse_domains.(System.get_env("HIVE_OIDC_ALLOWED_DOMAINS"))

github_client_id = System.get_env("HIVE_GITHUB_CLIENT_ID")
github_client_secret = System.get_env("HIVE_GITHUB_CLIENT_SECRET")
github_allowed = parse_domains.(System.get_env("HIVE_GITHUB_ALLOWED_DOMAINS"))

google_configured? = present?.(google_client_id) and present?.(google_client_secret)
oidc_configured? = present?.(oidc_issuer) and present?.(oidc_client_id)
github_configured? = present?.(github_client_id) and present?.(github_client_secret)

# Pre-filter the Google account picker with `hd=` when a single allowed
# domain is configured (Google's hosted-domain hint).
google_authorize_params =
  case google_allowed do
    [single] -> %{"hd" => single}
    _ -> %{}
  end

# Oidcc workers fetch each issuer's .well-known/openid-configuration at
# boot; only register issuers that have credentials so we don't spin up
# workers for unused providers.
issuers =
  Enum.filter(
    [
      google_configured? && %{name: :google, issuer: "https://accounts.google.com"},
      oidc_configured? && %{name: :oidc, issuer: oidc_issuer}
    ],
    & &1
  )

config :ueberauth_oidcc, :issuers, issuers

# Per-strategy credentials. ueberauth_oidcc's strategy reads these at
# request time from `:ueberauth_oidcc, :providers` and merges them on
# top of the compile-time options in config/config.exs. Only set the
# entries for providers whose env vars are present.
ueberauth_oidcc_providers =
  []
  |> then(fn acc ->
    if google_configured? do
      [
        google: [
          client_id: google_client_id,
          client_secret: google_client_secret,
          scopes: scopes,
          authorization_params: google_authorize_params
        ]
      ] ++ acc
    else
      acc
    end
  end)
  |> then(fn acc ->
    if oidc_configured? do
      [
        oidc: [
          client_id: oidc_client_id,
          client_secret: oidc_client_secret,
          scopes: scopes
        ]
      ] ++ acc
    else
      acc
    end
  end)

config :ueberauth_oidcc, :providers, ueberauth_oidcc_providers

# GitHub's strategy reads its credentials from this key at request time.
# Only set it when configured so the strategy stays dormant otherwise.
if github_configured? do
  config :ueberauth, Ueberauth.Strategy.Github.OAuth,
    client_id: github_client_id,
    client_secret: github_client_secret
end

# Display metadata + domain allowlists for each enabled provider. Hive
# consults this in the login page (button labels) and after Ueberauth's
# callback succeeds (domain check). Only providers that match an
# Ueberauth strategy above appear here.
hive_providers =
  []
  |> then(fn acc ->
    if google_configured? do
      [{:google, %{display_name: "Google", allowed_domains: google_allowed}} | acc]
    else
      acc
    end
  end)
  |> then(fn acc ->
    if oidc_configured? do
      [{:oidc, %{display_name: oidc_display_name, allowed_domains: oidc_allowed}} | acc]
    else
      acc
    end
  end)
  |> then(fn acc ->
    if github_configured? do
      [{:github, %{display_name: "GitHub", allowed_domains: github_allowed}} | acc]
    else
      acc
    end
  end)
  |> Enum.reverse()

config :hive, :auth,
  visibility: System.get_env("HIVE_VISIBILITY", "public"),
  providers: hive_providers,
  org_domains: parse_domains.(System.get_env("HIVE_ORG_DOMAINS"))

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  linux_keepalive_opts =
    case :os.type() do
      {:unix, :linux} ->
        [
          {:raw, 6, 4, <<60::native-32>>},
          {:raw, 6, 5, <<15::native-32>>},
          {:raw, 6, 6, <<4::native-32>>}
        ]

      _ ->
        []
    end

  database_ssl_opts =
    case System.get_env("DATABASE_SSL_CA_CERT_FILE") do
      nil -> [verify: :verify_none]
      "" -> [verify: :verify_none]
      path -> [cacertfile: path, verify: :verify_peer]
    end

  config :hive, Hive.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6 ++ [{:keepalive, true} | linux_keepalive_opts],
    ssl: System.get_env("DATABASE_SSL") in ~w(true 1),
    ssl_opts: database_ssl_opts,
    # Hive connects directly to Postgres (no transaction pooler), so bound how
    # long a stuck or severed connection can hold a row lock. Keepalive probes
    # let Postgres notice a dead client and release its locks, and
    # idle_in_transaction_session_timeout rolls back an abandoned writer so it
    # can't wedge the next writer.
    parameters: [
      tcp_keepalives_idle: "60",
      tcp_keepalives_interval: "30",
      tcp_keepalives_count: "3",
      idle_in_transaction_session_timeout: "60s"
    ]

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

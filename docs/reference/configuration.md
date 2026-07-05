# Configuration reference

Hive is configured with environment variables. Keep secrets in the
runtime environment or in your deployment secret manager, not in source
control.

## Core runtime

### SECRET_KEY_BASE {#secret_key_base}

Required in production. Phoenix uses this secret to sign and encrypt
session data. Generate it with `mix phx.gen.secret`.

### DATABASE_URL {#database_url}

Required in production. PostgreSQL connection string, for example
`ecto://USER:PASS@HOST/DATABASE`.

### PHX_HOST {#phx_host}

Public host name used to build absolute application links in production.

### PORT {#port}

Hypertext Transfer Protocol
([HTTP](https://developer.mozilla.org/en-US/docs/Web/HTTP)) port the
Phoenix endpoint listens on. Defaults to `4000`.

### POOL_SIZE {#pool_size}

PostgreSQL connection pool size. Defaults to `10`.

### DATABASE_SSL {#database_ssl}

Set to `true` or `1` to connect to PostgreSQL with Transport Layer
Security ([TLS](https://www.cloudflare.com/learning/ssl/transport-layer-security-tls/)).

### DATABASE_SSL_CA_CERT_FILE {#database_ssl_ca_cert_file}

Path to the certificate authority file used to verify the PostgreSQL
server certificate when database TLS verification is required.

### ECTO_IPV6 {#ecto_ipv6}

Set to `true` or `1` when the database connection should use Internet
Protocol version 6 ([IPv6](https://en.wikipedia.org/wiki/IPv6)).

## Access control

### HIVE_VISIBILITY {#hive_visibility}

Controls anonymous access to the dashboard. `public` allows anonymous
visitors to view public content. `private` requires sign-in before any
dashboard page loads.

### HIVE_ORG_DOMAINS {#hive_org_domains}

Comma-separated email domains that become organization members at
signup. When unset, every signed-in user becomes a member.

## Authentication providers

### HIVE_GOOGLE_CLIENT_ID {#hive_google_client_id}

Google OAuth 2.0 ([OAuth](https://oauth.net/2/)) client identifier for
Google sign-in.

### HIVE_GOOGLE_CLIENT_SECRET {#hive_google_client_secret}

Google OAuth 2.0 client secret for Google sign-in.

### HIVE_GOOGLE_ALLOWED_DOMAINS {#hive_google_allowed_domains}

Optional comma-separated email domain allowlist for Google sign-in. When
exactly one domain is set, Hive also sends Google's hosted-domain hint to
the account picker.

### HIVE_OIDC_ISSUER {#hive_oidc_issuer}

Issuer base address for a generic OpenID Connect
([OIDC](https://openid.net/developers/how-connect-works/)) provider.
Hive discovers provider endpoints from
`<issuer>/.well-known/openid-configuration`.

### HIVE_OIDC_CLIENT_ID {#hive_oidc_client_id}

Generic OpenID Connect client identifier.

### HIVE_OIDC_CLIENT_SECRET {#hive_oidc_client_secret}

Optional generic OpenID Connect client secret.

### HIVE_OIDC_DISPLAY_NAME {#hive_oidc_display_name}

Optional label for the generic OpenID Connect login button. Defaults to
`Identity provider`.

### HIVE_OIDC_ALLOWED_DOMAINS {#hive_oidc_allowed_domains}

Optional comma-separated email domain allowlist for generic OpenID
Connect sign-in.

### HIVE_GITHUB_CLIENT_ID {#hive_github_client_id}

GitHub OAuth 2.0 client identifier for GitHub sign-in.

### HIVE_GITHUB_CLIENT_SECRET {#hive_github_client_secret}

GitHub OAuth 2.0 client secret for GitHub sign-in.

### HIVE_GITHUB_ALLOWED_DOMAINS {#hive_github_allowed_domains}

Optional comma-separated email domain allowlist for GitHub sign-in.

## GitHub app

### HIVE_GITHUB_APP_ID {#hive_github_app_id}

GitHub App identifier used for repository and webhook integrations.

### HIVE_GITHUB_APP_INSTALLATION_ID {#hive_github_app_installation_id}

GitHub App installation identifier.

### HIVE_GITHUB_APP_PRIVATE_KEY {#hive_github_app_private_key}

Private key for the GitHub App installation.

### HIVE_GITHUB_WEBHOOK_SECRET {#hive_github_webhook_secret}

Webhook signing secret for GitHub events.

### HIVE_GITHUB_API_URL {#hive_github_api_url}

Optional GitHub application programming interface
([API](https://en.wikipedia.org/wiki/API)) base address. Defaults to
`https://api.github.com`.

## Agent Model Provider {#agent-model-provider}

### HIVE_LLM_API_KEY {#hive_llm_api_key}

Fallback provider key for features backed by a
[large language model](https://en.wikipedia.org/wiki/Large_language_model).
Agentic workflows prefer the profile marked **Use for Hive inference** in
the dashboard. When no profile is marked and this value is unset,
agentic workflows stay dormant.

### HIVE_LLM_MODEL {#hive_llm_model}

Fallback model identifier in `provider:model_id` form. Required when
`HIVE_LLM_API_KEY` is set.

### HIVE_LLM_BASE_URL {#hive_llm_base_url}

Optional fallback provider endpoint override for OpenAI-compatible
gateways or self-hosted providers.

## Model Gateway {#model-gateway}

### HIVE_INFERENCE_PROVIDERS {#hive_inference_providers}

JavaScript Object Notation
([JSON](https://www.json.org/json-en.html)) object that declares one or
more upstream model providers for the model gateway.

### HIVE_INFERENCE_UPSTREAM_ID {#hive_inference_upstream_id}

Identifier for the single upstream provider shorthand. Defaults to
`default`.

### HIVE_INFERENCE_UPSTREAM_BASE_URL {#hive_inference_upstream_base_url}

Base address for the single upstream provider shorthand.

### HIVE_INFERENCE_UPSTREAM_API_KEY {#hive_inference_upstream_api_key}

Optional provider key for the single upstream provider shorthand.

### HIVE_INFERENCE_UPSTREAM_TIMEOUT {#hive_inference_upstream_timeout}

Optional upstream request timeout for the single upstream provider
shorthand.

## Object storage

### HIVE_OBJECT_STORAGE_PROVIDER {#hive_object_storage_provider}

Object storage backend. Use `none` to disable object storage or `s3` to
use Amazon Simple Storage Service
([S3](https://aws.amazon.com/s3/))-compatible storage.

### HIVE_S3_BUCKET {#hive_s3_bucket}

Object storage bucket name.

### HIVE_S3_REGION {#hive_s3_region}

Object storage region. Defaults to `us-east-1`.

### HIVE_S3_ENDPOINT_URL {#hive_s3_endpoint_url}

Endpoint address for S3-compatible providers.

### HIVE_S3_ACCESS_KEY_ID {#hive_s3_access_key_id}

Access key identifier for S3-compatible object storage.

### HIVE_S3_SECRET_ACCESS_KEY {#hive_s3_secret_access_key}

Secret access key for S3-compatible object storage.

### HIVE_S3_PUBLIC_BASE_URL {#hive_s3_public_base_url}

Optional public base address for generated object links.

### HIVE_S3_FORCE_PATH_STYLE {#hive_s3_force_path_style}

Set to `true` or `1` for S3-compatible providers that require
path-style bucket addressing.

## Slack

### HIVE_SLACK_CLIENT_ID {#hive_slack_client_id}

Slack app client identifier.

### HIVE_SLACK_CLIENT_SECRET {#hive_slack_client_secret}

Slack app client secret.

### HIVE_SLACK_SIGNING_SECRET {#hive_slack_signing_secret}

Slack app signing secret used to verify incoming Slack requests.

### HIVE_SLACK_BOT_SCOPES {#hive_slack_bot_scopes}

Optional comma-separated Slack bot OAuth 2.0 scope list. Defaults to
the scopes Hive needs for installation, message capture, replies, and
link unfurling.

### HIVE_SLACK_ALLOWED_TEAM_IDS {#hive_slack_allowed_team_ids}

Optional comma-separated Slack workspace identifier allowlist.

## Observability

### SENTRY_DSN {#sentry_dsn}

Sentry Data Source Name
([DSN](https://docs.sentry.io/product/sentry-basics/dsn-explainer/)) for
error reporting. When unset, Sentry reporting is disabled.

### SENTRY_ENVIRONMENT {#sentry_environment}

Deployment environment tag for Sentry events.

### SENTRY_RELEASE {#sentry_release}

Release tag for Sentry events.

### SENTRY_OBAN_CAPTURE_ERRORS {#sentry_oban_capture_errors}

Set to `true` or `1` to capture failed Oban job attempts. Defaults to
`true`.

### SENTRY_OBAN_REPORT_RETRIES {#sentry_oban_report_retries}

Set to `true` or `1` to report retryable Oban failures before their
final attempt. Defaults to `false`.

### SENTRY_OBAN_CRON_MONITORING {#sentry_oban_cron_monitoring}

Set to `true` or `1` to send Sentry check-ins for scheduled Oban jobs.
Defaults to `true`.

## Vector database

### HIVE_OPENDATA_VECTOR_URL {#hive_opendata_vector_url}

Optional base address for the bundled vector service used by semantic
search.

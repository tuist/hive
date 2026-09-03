# Configuration reference

Hive is configured with environment variables. Keep secrets in the
runtime environment or in your deployment secret manager, not in source
control. The deployment platform must provide the required database and
application settings.

## Core runtime

### SECRET_KEY_BASE {#secret_key_base}

Required in production. Hive uses this value to protect session data.
Generate it with `mix phx.gen.secret` or another cryptographically secure
64-byte random-value generator.

### DATABASE_URL {#database_url}

Required for direct container deployments. PostgreSQL connection string, for example
`ecto://USER:PASS@HOST/DATABASE`.

### PHX_HOST {#phx_host}

Public host name used to build application links. Set it to the deployed
Hive domain.

### PORT {#port}

Hypertext Transfer Protocol
([HTTP](https://developer.mozilla.org/en-US/docs/Web/HTTP)) port Hive
listens on. Defaults to `4000`.

### POOL_SIZE {#pool_size}

PostgreSQL connection pool size. Defaults to `10`.

### DATABASE_SSL {#database_ssl}

Set to `true` or `1` to connect to PostgreSQL with Transport Layer
Security ([TLS](https://www.cloudflare.com/learning/ssl/transport-layer-security-tls/)).

### DATABASE_SSL_CA_CERT_FILE {#database_ssl_ca_cert_file}

Path to the certificate authority file used to verify the PostgreSQL
server certificate when secure connection verification is required.

### ECTO_IPV6 {#ecto_ipv6}

Set to `true` or `1` when the database connection should use Internet
Protocol version 6 ([IPv6](https://en.wikipedia.org/wiki/IPv6)). Optional.

## Branding

### HIVE_PRODUCT_NAME {#hive_product_name}

Name the instance presents itself with in the header, page titles, login
screen, and link previews. Defaults to `Hive`.

### HIVE_LOGO_URL {#hive_logo_url}

Absolute Uniform Resource Locator
([URL](https://developer.mozilla.org/en-US/docs/Learn/Common_questions/Web_mechanics/What_is_a_URL))
of the image used as the header logo, the favicon, and the mark on
generated link-preview images. It must be publicly reachable from both
the browser and the instance itself. Defaults to the bundled Hive logo.
A square image of at least 256 by 256 pixels reproduces best. If the
image cannot be fetched, link previews fall back to the bundled logo.

## Access control

### HIVE_VISIBILITY {#hive_visibility}

Controls anonymous access to the dashboard. `public` allows anonymous
visitors to view public content. `private` requires sign-in before any
dashboard page loads.

### HIVE_ORG_DOMAINS {#hive_org_domains}

Comma-separated email domains that become organization members at
signup. When unset, every signed-in user becomes a member.

## Email notifications

Email delivery is disabled by default. People can still save notification
preferences while it is disabled, but Hive does not send messages until a
provider and sender are configured. Daily summaries are sent at 08:00
Coordinated Universal Time.

### HIVE_EMAIL_PROVIDER {#hive_email_provider}

Selects the outgoing email provider. Use `none` to disable delivery,
`postmark` for [Postmark](https://postmarkapp.com/), or `smtp` for a
[Simple Mail Transfer Protocol](https://www.cloudflare.com/learning/email-security/what-is-smtp/)
server. Defaults to `none`.

### HIVE_EMAIL_FROM {#hive_email_from}

Verified sender address used for notification email. Write it on its own
(`notifications@example.com`) or with a display name
(`Hive <notifications@example.com>`); readers see the display name and the
mail server receives the address. Required when email delivery is enabled,
and Hive refuses to start when the value is not an email address.

### HIVE_POSTMARK_SERVER_TOKEN {#hive_postmark_server_token}

Postmark server token. Required when `HIVE_EMAIL_PROVIDER=postmark`.

### HIVE_EMAIL_MESSAGE_STREAM {#hive_email_message_stream}

Optional Postmark message stream. Leave it unset to use the server's default
transactional stream.

### HIVE_SMTP_RELAY {#hive_smtp_relay}

Host name of the outgoing Simple Mail Transfer Protocol server. Required when
`HIVE_EMAIL_PROVIDER=smtp`.

### HIVE_SMTP_PORT {#hive_smtp_port}

Port for the outgoing mail server. Defaults to `587`. Port `465` enables
implicit Transport Layer Security; other ports require the server to upgrade
the connection with Transport Layer Security.

### HIVE_SMTP_USERNAME {#hive_smtp_username}

Optional outgoing mail username. Set it together with `HIVE_SMTP_PASSWORD`.

### HIVE_SMTP_PASSWORD {#hive_smtp_password}

Optional outgoing mail password. Set it together with `HIVE_SMTP_USERNAME`.

## Authentication providers

### HIVE_GOOGLE_CLIENT_ID {#hive_google_client_id}

Google Open Authorization ([OAuth 2.0](https://oauth.net/2/)) client
identifier for Google sign-in.

### HIVE_GOOGLE_CLIENT_SECRET {#hive_google_client_secret}

Google Open Authorization 2.0 client secret for Google sign-in.

### HIVE_GOOGLE_ALLOWED_DOMAINS {#hive_google_allowed_domains}

Optional comma-separated email domain allowlist for Google sign-in. When
exactly one domain is set, Hive also sends Google's hosted-domain hint to
the account picker.

### HIVE_OIDC_ISSUER {#hive_oidc_issuer}

Issuer base address for a generic
[OpenID Connect](https://openid.net/developers/how-connect-works/)
provider.
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

GitHub Open Authorization 2.0 client identifier for GitHub sign-in.

### HIVE_GITHUB_CLIENT_SECRET {#hive_github_client_secret}

GitHub Open Authorization 2.0 client secret for GitHub sign-in.

### HIVE_GITHUB_ALLOWED_DOMAINS {#hive_github_allowed_domains}

Optional comma-separated email domain allowlist for GitHub sign-in.

## GitHub App

### HIVE_GITHUB_APP_ID {#hive_github_app_id}

GitHub App identifier used for repository and webhook integrations.

### HIVE_GITHUB_APP_INSTALLATION_ID {#hive_github_app_installation_id}

GitHub App installation identifier.

### HIVE_GITHUB_APP_PRIVATE_KEY {#hive_github_app_private_key}

Private key for the GitHub App installation. Accepts Privacy Enhanced
Mail text or a base64-encoded value.

### HIVE_GITHUB_WEBHOOK_SECRET {#hive_github_webhook_secret}

Optional signing secret for requests sent to `/webhooks/github`.

### HIVE_GITHUB_API_URL {#hive_github_api_url}

Optional GitHub application programming interface
([API](https://en.wikipedia.org/wiki/API)) base address. Defaults to
`https://api.github.com`.

## Agent Model Provider {#agent-model-provider}

### HIVE_LLM_API_KEY {#hive_llm_api_key}

Fallback provider key for features backed by a
[large language model](https://en.wikipedia.org/wiki/Large_language_model).
Agentic workflows prefer the profile marked **Use for Hive inference** in
the dashboard. Flights first prefer the profile marked **Use for Hive
coding**, then fall back to the general inference profile. When no applicable
profile is marked and this value is unset, agentic workflows stay dormant.

### HIVE_LLM_MODEL {#hive_llm_model}

Fallback model identifier in `provider:model_id` form, for example
`anthropic:claude-haiku-4-5`. Required when `HIVE_LLM_API_KEY` is set.
For an OpenAI-compatible gateway such as Together.ai, use the `openai:`
prefix together with `HIVE_LLM_BASE_URL`.

### HIVE_LLM_BASE_URL {#hive_llm_base_url}

Optional fallback provider endpoint override for OpenAI-compatible
gateways or self-hosted providers.

## Flight runners {#coding-runs}

Flights require a profile marked **Use for Hive coding**, a general Hive
inference profile, or the launch-time model configuration. They also require a
configured GitHub App and one of the sandbox runners below. They are disabled
when any required part is missing. The model and GitHub credentials stay in
Hive and are never passed into the sandbox.

### HIVE_CODING_RUNNER {#hive_coding_runner}

Names the sandbox provider used for new Flights. Use `microsandbox` for
local development, `kubernetes` for production on
[Kubernetes Agent Sandbox](https://agent-sandbox.sigs.k8s.io/), or `disabled`
to turn Flights off. The default is `microsandbox` in development and
`disabled` in other environments.

The local runner requires the `microsandbox` executable installed by
`mise install`. The Kubernetes runner requires Agent Sandbox 0.5.1 or newer,
a gVisor runtime class, and permission for Hive to create Sandbox resources
and execute commands in their pods.

Other names select a custom provider supplied through
`HIVE_CODING_SANDBOX_MODULE`. The name is stored with each Flight, so keep it
stable when changing that provider's implementation.

### HIVE_CODING_SANDBOX_MODULE {#hive_coding_sandbox_module}

Fully qualified Elixir module for a custom sandbox provider. The module must be
compiled into the Hive release and implement the
[Condukt sandbox behaviour](https://github.com/tuist/condukt/blob/main/lib/condukt/sandbox.ex).
Hive validates the required file, search, and command operations before
enabling Flights. Built-in `microsandbox` and `kubernetes` providers ignore
this setting.

Hive creates the repository baseline after the custom provider starts. The
provider is responsible only for creating the isolated environment and
implementing the Condukt operations. It must provide a Unix-compatible shell
and use `/workspace` as its working directory.

### HIVE_CODING_SANDBOX_OPTIONS {#hive_coding_sandbox_options}

JavaScript Object Notation
([JSON](https://www.json.org/json-en.html)) object containing runner-specific
options. Custom providers receive it unchanged, which allows adapters for
services such as [Daytona](https://www.daytona.io/) or
[E2B](https://e2b.dev/) without adding provider settings to Hive itself.
Defaults to an empty object.

Options may contain provider credentials. Keep them in the deployment secret
manager and never commit them to the repository.

The Kubernetes provider accepts:

| Field | Behavior |
| --- | --- |
| `in_cluster` | Uses Hive's mounted Kubernetes service-account identity. Set this to `true` for normal deployments. |
| `kubeconfig` | Uses a kubeconfig file instead of the in-cluster identity. Intended for development and diagnostics. |
| `namespace` | Namespace where Sandbox resources are created. Defaults to `hive-sandboxes`. |
| `runtime_class_name` | Runtime class enforced on every sandbox. Defaults to `gvisor`. |
| `service_account` | Service account assigned to sandbox pods. Its token is never mounted. |
| `image_pull_policy` | Kubernetes image-pull policy for the coding image. Defaults to `IfNotPresent`. |
| `node_selector` | Labels that select dedicated sandbox worker nodes. |
| `tolerations` | Tolerations required by dedicated, tainted sandbox workers. |
| `image_pull_secrets` | Names of image-pull secrets available in the sandbox namespace. |
| `ready_timeout_ms` | Maximum time to wait for Agent Sandbox to report ready. Defaults to `120000`. |

The Hive chart produces this object from `codingRuns.kubernetes` values. It
also creates the namespace-scoped permissions, service account, network
policy, and resource quota. The cluster operator must install
[Agent Sandbox](https://agent-sandbox.sigs.k8s.io/docs/getting_started/install_prerequisites/)
and configure gVisor on the selected worker nodes before enabling the runner.

### HIVE_MICROSANDBOX_HOME {#hive_microsandbox_home}

Optional state directory for the local microsandbox runtime. Hive defaults to
the short application-specific `/tmp/hive-msb` directory so Unix socket paths
remain within operating-system limits and Flights do not share runtime
metadata with manually managed local sandboxes.

### HIVE_CODING_IMAGE {#hive_coding_image}

Open Container Initiative
([OCI](https://opencontainers.org/)) image used for each isolated run.
Defaults to `ubuntu:24.04`.

The default image can inspect and edit code after the setup command installs
Git and ripgrep. To run repository validation, use a pinned image containing
that repository's build tools or extend `HIVE_CODING_SETUP_COMMAND` to install
them. Production deployments should use an immutable image tag.

### HIVE_CODING_CPUS {#hive_coding_cpus}

Virtual processor count assigned to each sandbox. Defaults to `2`.

### HIVE_CODING_MEMORY_MIB {#hive_coding_memory_mib}

Sandbox memory in mebibytes. Defaults to `4096`.

### HIVE_CODING_DISK_MIB {#hive_coding_disk_mib}

Scratch-disk capacity in mebibytes. Defaults to `8192`. Kubernetes applies it
as the workspace's ephemeral-volume size limit. The local microsandbox
provider does not use this setting.

### HIVE_CODING_TIMEOUT_MINUTES {#hive_coding_timeout_minutes}

Maximum duration of one Flight in minutes. Defaults to `30`. Hive also
sets the remote sandbox's automatic cleanup timer beyond this limit.

### HIVE_CODING_SETUP_COMMAND {#hive_coding_setup_command}

Shell command executed once after the sandbox starts and before the coding
harness receives control. The default installs Git, ripgrep, and certificate
authority data with Ubuntu's package manager. Set it to `true` when a custom
image already contains every required tool.

The setup command is operator-controlled. Alert content and model output are
never interpolated into it. Kubernetes sandboxes run as a non-root user, so
their image should already contain required system packages and normally use
`true` as the setup command.

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
For Together.ai, use `https://api.together.ai/v1`.

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

Optional comma-separated Slack bot authorization scope list. Defaults to
the scopes Hive needs for installation, message capture, replies, and
link unfurling.

### HIVE_SLACK_ALLOWED_TEAM_IDS {#hive_slack_allowed_team_ids}

Optional comma-separated Slack workspace identifier allowlist.

## ClickHouse

### HIVE_CLICKHOUSE_ENABLED {#hive_clickhouse_enabled}

Set to `true` or `1` to connect Hive to
[ClickHouse](https://clickhouse.com/). It defaults to enabled in development
and disabled in other environments. The Helm chart configures the connection
automatically when `clickhouse.enabled=true`.

### HIVE_CLICKHOUSE_HOST {#hive_clickhouse_host}

ClickHouse host name. Defaults to `localhost`.

### HIVE_CLICKHOUSE_PORT {#hive_clickhouse_port}

ClickHouse Hypertext Transfer Protocol port. Defaults to `8123`.

### HIVE_CLICKHOUSE_DATABASE {#hive_clickhouse_database}

ClickHouse database name. Defaults to `hive` in production. In development,
Hive derives a database name from the same per-worktree suffix used for its
PostgreSQL database, so concurrent checkouts do not share data.

### HIVE_CLICKHOUSE_USERNAME {#hive_clickhouse_username}

ClickHouse user name. Defaults to `default`.

### HIVE_CLICKHOUSE_PASSWORD {#hive_clickhouse_password}

ClickHouse password. The Helm chart derives this from the existing Hive
application secret, so it does not require another stored credential.

### HIVE_CLICKHOUSE_POOL_SIZE {#hive_clickhouse_pool_size}

Maximum number of ClickHouse connections for each read and write pool.
Defaults to `5`.

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

Set to `true` or `1` to report background tasks that exhaust their
attempts. Defaults to `true`.

### SENTRY_OBAN_REPORT_RETRIES {#sentry_oban_report_retries}

Set to `true` or `1` to report retryable background-task failures before
their final attempt. Defaults to `false`.

### SENTRY_OBAN_CRON_MONITORING {#sentry_oban_cron_monitoring}

Set to `true` or `1` to send Sentry check-ins for scheduled tasks.
Defaults to `true`.

## Vector database

### HIVE_OPENDATA_VECTOR_URL {#hive_opendata_vector_url}

Optional base address for a compatible vector service. Current
deployments can leave it unset unless a feature explicitly requires
vector search.

defmodule Hive.Errors.ProjectKey do
  @moduledoc """
  A Data Source Name ([DSN](https://docs.sentry.io/product/sentry-basics/dsn-explainer/))
  minted for a project, optionally scoped to a single domain. The
  `public_key` is the identifier SDKs send in the `X-Sentry-Auth` header
  (or `sentry_key` query parameter). The `secret_key` is a Sentry legacy
  field kept for compatibility with older SDKs; modern SDKs ignore it.

  When `domain_id` is set, the row represents a domain-scoped DSN:
  events ingested through it are attributed to both the project and the
  domain at the credential layer, so a service that maps to one domain
  never has to add an SDK tag to land classified. Every project also has
  a plain project-level DSN (`domain_id: nil`) that catches everything
  else — one-off scripts, crons, and any subsystem that isn't dedicated
  to a single domain.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Accounts.User
  alias Hive.Domains.Domain
  alias Hive.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "errors_project_keys" do
    field :dsn_project_id, :integer, read_after_writes: true
    field :public_key, :string
    field :secret_key, :string
    field :name, :string, default: "default"
    field :last_used_at, :utc_datetime_usec

    belongs_to :project, Project
    belongs_to :domain, Domain
    belongs_to :created_by, User, foreign_key: :created_by_user_id

    timestamps(type: :utc_datetime)
  end

  def changeset(project_key, attrs) do
    project_key
    |> cast(attrs, [
      :project_id,
      :domain_id,
      :public_key,
      :secret_key,
      :name,
      :created_by_user_id
    ])
    |> validate_required([:project_id, :public_key, :name])
    |> validate_length(:public_key, is: 32)
    |> validate_length(:secret_key, is: 32)
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:public_key)
    |> unique_constraint([:project_id, :domain_id],
      name: :errors_project_keys_project_id_domain_id_index,
      message: "domain already has a DSN for this project"
    )
  end

  @doc """
  Generates a random 32-character hex key suitable for the `public_key`
  or `secret_key` field.
  """
  def generate_key do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  @doc """
  Renders the DSN string SDKs consume, given a host built from the
  endpoint URL and the numeric project id required by Sentry clients.
  """
  def dsn(%__MODULE__{public_key: public_key, dsn_project_id: project_id}, endpoint_url)
      when is_binary(endpoint_url) do
    uri = URI.parse(endpoint_url)
    scheme = uri.scheme || "https"
    host = uri.host
    port = if uri.port in [nil, 80, 443], do: "", else: ":#{uri.port}"
    "#{scheme}://#{public_key}@#{host}#{port}/#{project_id}"
  end
end

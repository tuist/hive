defmodule Hive.Auth do
  @moduledoc """
  Auth glue around Ueberauth.

  Ueberauth owns the OAuth/OIDC dance; this module exposes the small set
  of helpers Hive needs around it: whether auth is required, what
  providers should appear on the login screen, whether a given email is
  allowed for a given provider's domain allowlist, and what role a
  signed-in user has.

  Hive is single-tenant: the deployment *is* the organization. A user is
  either a **member** of the org (their email domain is one of the
  configured org domains) or an external **contributor** (authenticated,
  but from outside). Role is derived from the email on each request, not
  stored, so changing the org domains reclassifies users without a
  migration. When no org domains are configured, everyone who can sign
  in is treated as a member (the natural default for a private instance
  where logging in already implies you're staff).
  """

  alias Hive.Accounts
  alias Hive.Accounts.User

  @product_name "Hive"

  def product_name, do: @product_name

  @doc """
  Returns the configured visibility: `"public"` (default) or `"private"`.
  Driven by `HIVE_VISIBILITY` at runtime.
  """
  def visibility do
    :hive
    |> Application.get_env(:auth, [])
    |> Keyword.get(:visibility, "public")
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  @doc "True when the instance gates routes behind authentication."
  def private?, do: visibility() == "private"

  @doc "True when anyone can reach the dashboard without logging in."
  def public?, do: not private?()

  @doc """
  Returns the list of providers configured for this instance, in the
  order they should appear on the login screen. Each entry is a tuple
  of `{key :: atom, %{display_name: String.t(), allowed_domains: [String.t()]}}`.
  """
  def providers do
    :hive
    |> Application.get_env(:auth, [])
    |> Keyword.get(:providers, [])
  end

  @doc "Metadata for a single provider, or `nil` if not configured."
  def provider(key) when is_atom(key) do
    providers() |> Enum.find_value(fn {k, meta} -> if k == key, do: meta end)
  end

  @doc """
  Checks an authenticated email against a provider's allowed-domains
  list. Returns `:ok` when allowed (or when no list is set), or
  `{:error, :domain_not_allowed}` when rejected. `nil` (unknown
  provider) is rejected.

  Pure function — pass `provider/1`'s result to it explicitly:

      provider = Hive.Auth.provider(:google)
      Hive.Auth.check_domain(provider, email)
  """
  def check_domain(nil, _email), do: {:error, :domain_not_allowed}
  def check_domain(%{allowed_domains: []}, _email), do: :ok

  def check_domain(%{allowed_domains: domains}, email) when is_binary(email) do
    domain = email |> String.split("@", parts: 2) |> List.last() |> String.downcase()
    if domain in domains, do: :ok, else: {:error, :domain_not_allowed}
  end

  def check_domain(_provider, _email), do: {:error, :domain_not_allowed}

  @doc """
  Domains whose accounts count as members of this org. Driven by
  `HIVE_ORG_DOMAINS` at runtime; empty means "treat every signed-in
  user as a member".
  """
  def org_domains do
    :hive
    |> Application.get_env(:auth, [])
    |> Keyword.get(:org_domains, [])
  end

  @doc """
  Role of a user relative to the org this instance represents:

  - `:anonymous` — not signed in
  - `:member` — email domain is one of `org_domains/0` (or no org
    domains are configured)
  - `:contributor` — signed in, but from outside the org

  Takes the org domains explicitly (defaulting to `org_domains/0`) so the
  classification can be tested without touching global config.
  """
  def role(user, domains \\ org_domains())
  def role(nil, _domains), do: :anonymous
  def role(%User{}, []), do: :member

  def role(%User{email: email}, domains) do
    if email_domain(email) in domains, do: :member, else: :contributor
  end

  @doc "True when the user is a member of the org."
  def member?(user), do: role(user) == :member

  @doc "True when the user is signed in but not a member of the org."
  def contributor?(user), do: role(user) == :contributor

  @doc """
  The persisted user for the current session, or `nil`. The session
  stores only the user id; the record is loaded on demand.
  """
  def current_user(conn) do
    conn
    |> Plug.Conn.get_session(:user_id)
    |> Accounts.get_user()
  end

  defp email_domain(email) when is_binary(email) do
    email |> String.split("@", parts: 2) |> List.last() |> String.downcase()
  end

  defp email_domain(_email), do: ""
end

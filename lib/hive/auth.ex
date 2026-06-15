defmodule Hive.Auth do
  @moduledoc """
  Auth glue around Ueberauth.

  Ueberauth owns the OAuth/OIDC dance; this module exposes the small set
  of helpers Hive needs around it: whether auth is required, what
  providers should appear on the login screen, whether a given email is
  allowed for a given provider's domain allowlist, and what role a
  signed-in user has.

  Hive is single-tenant: the deployment *is* the organization. Every
  signed-in user holds one persisted role on `Hive.Accounts.User`,
  ordered weakest to strongest: `:collaborator` (signed in, outside the
  org), `:member` (part of the org), `:admin` (explicitly promoted). The
  role is derived from the email domain at signup (see
  `HIVE_ORG_DOMAINS`) and then stored, so changing the org domain list
  afterwards does not reclassify existing users. Promote and demote with
  `Hive.Accounts.update_user_role/2`.
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

  @doc "Ueberauth strategy configuration for a single provider, or `nil` if missing."
  def ueberauth_provider(key) when is_atom(key) do
    :ueberauth
    |> Application.get_env(Ueberauth, [])
    |> Keyword.get(:providers, [])
    |> Keyword.get(key)
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
  The user's persisted role, or `:anonymous` when not signed in. The
  three signed-in values are `:collaborator`, `:member`, and `:admin`;
  see `Hive.Accounts.User` for what each one means.
  """
  def role(nil), do: :anonymous
  def role(%User{role: role}), do: role

  @doc """
  True when the user is part of the org. Both `:member` and `:admin`
  qualify, since admin is a strict superset of member.
  """
  def member?(%User{role: role}) when role in [:member, :admin], do: true
  def member?(_user), do: false

  @doc "True when the user is signed in but not part of the org."
  def collaborator?(%User{role: :collaborator}), do: true
  def collaborator?(_user), do: false

  @doc "True when the user's persisted role is `:admin`."
  def admin?(%User{role: :admin}), do: true
  def admin?(_user), do: false

  @doc """
  The persisted user for the current session, or `nil`. The session
  stores only the user id; the record is loaded on demand.
  """
  def current_user(conn) do
    conn
    |> Plug.Conn.get_session(:user_id)
    |> Accounts.get_user()
  end
end

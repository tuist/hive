defmodule Hive.Auth do
  @moduledoc """
  Auth glue around Ueberauth.

  Ueberauth owns the OAuth/OIDC dance; this module exposes the small set
  of helpers Hive needs around it: whether auth is required, what
  providers should appear on the login screen, and whether a given
  email is allowed for a given provider's domain allowlist.
  """

  @product_name "Hive"

  def enabled? do
    mode() == "oidc"
  end

  def mode do
    :hive
    |> Application.get_env(:auth, [])
    |> Keyword.get(:mode, "none")
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  def product_name, do: @product_name

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
  Checks an authenticated email against the provider's allowed-domains
  list. Returns `:ok` when allowed (or when no list is set), or
  `{:error, :domain_not_allowed}` when rejected.
  """
  def check_domain(key, email) when is_atom(key) and is_binary(email) do
    case provider(key) do
      %{allowed_domains: []} ->
        :ok

      %{allowed_domains: domains} ->
        domain = email |> String.split("@", parts: 2) |> List.last() |> String.downcase()
        if domain in domains, do: :ok, else: {:error, :domain_not_allowed}

      _ ->
        {:error, :domain_not_allowed}
    end
  end

  def check_domain(_key, _email), do: {:error, :domain_not_allowed}

  def current_user(conn), do: Plug.Conn.get_session(conn, :current_user)
end

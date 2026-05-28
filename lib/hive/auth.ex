defmodule Hive.Auth do
  @moduledoc false

  @default_scopes "openid profile email"

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

  def product_name do
    :hive
    |> Application.get_env(:auth, [])
    |> Keyword.get(:product_name, "Hive")
  end

  def product_tagline do
    :hive
    |> Application.get_env(:auth, [])
    |> Keyword.get(:product_tagline, "Product work orchestration")
  end

  def provider_name do
    :hive
    |> Application.get_env(:auth, [])
    |> Keyword.get(:provider_name, "Identity provider")
  end

  def oidc_config do
    auth = Application.get_env(:hive, :auth, [])

    %{
      authorize_url: Keyword.get(auth, :oidc_authorize_url),
      token_url: Keyword.get(auth, :oidc_token_url),
      userinfo_url: Keyword.get(auth, :oidc_userinfo_url),
      client_id: Keyword.get(auth, :oidc_client_id),
      client_secret: Keyword.get(auth, :oidc_client_secret),
      scopes: Keyword.get(auth, :oidc_scopes, @default_scopes)
    }
  end

  def oidc_ready? do
    config = oidc_config()

    present?(config.authorize_url) and present?(config.token_url) and present?(config.client_id)
  end

  def current_user(conn), do: Plug.Conn.get_session(conn, :current_user)

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end

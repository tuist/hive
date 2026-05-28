defmodule Hive.Auth do
  @moduledoc false

  @google_authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @google_userinfo_url "https://openidconnect.googleapis.com/v1/userinfo"
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

  def providers do
    Enum.reject([google_provider(), oidc_provider()], &is_nil/1)
  end

  def provider(key) when is_binary(key) do
    Enum.find(providers(), &(&1.key == key))
  end

  def current_user(conn), do: Plug.Conn.get_session(conn, :current_user)

  defp google_provider do
    auth = Application.get_env(:hive, :auth, [])
    client_id = Keyword.get(auth, :google_client_id)
    client_secret = Keyword.get(auth, :google_client_secret)

    if present?(client_id) and present?(client_secret) do
      allowed_domains = parse_domains(Keyword.get(auth, :google_allowed_domains))

      %{
        key: "google",
        display_name: "Google",
        authorize_url: @google_authorize_url,
        token_url: @google_token_url,
        userinfo_url: @google_userinfo_url,
        client_id: client_id,
        client_secret: client_secret,
        scopes: Keyword.get(auth, :google_scopes, @default_scopes),
        allowed_domains: allowed_domains,
        authorize_params: google_authorize_params(allowed_domains)
      }
    end
  end

  defp google_authorize_params([single]), do: %{"hd" => single}
  defp google_authorize_params(_), do: %{}

  defp parse_domains(nil), do: []

  defp parse_domains(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp oidc_provider do
    auth = Application.get_env(:hive, :auth, [])
    client_id = Keyword.get(auth, :oidc_client_id)
    authorize_url = Keyword.get(auth, :oidc_authorize_url)
    token_url = Keyword.get(auth, :oidc_token_url)

    if present?(client_id) and present?(authorize_url) and present?(token_url) do
      %{
        key: "oidc",
        display_name: Keyword.get(auth, :provider_name, "Identity provider"),
        authorize_url: authorize_url,
        token_url: token_url,
        userinfo_url: Keyword.get(auth, :oidc_userinfo_url),
        client_id: client_id,
        client_secret: Keyword.get(auth, :oidc_client_secret),
        scopes: Keyword.get(auth, :oidc_scopes, @default_scopes),
        allowed_domains: parse_domains(Keyword.get(auth, :oidc_allowed_domains)),
        authorize_params: %{}
      }
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end

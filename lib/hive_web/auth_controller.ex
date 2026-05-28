defmodule HiveWeb.AuthController do
  use HiveWeb, :controller

  alias Hive.Auth
  alias HiveWeb.PageHTML

  def new(conn, _params) do
    html(conn, Phoenix.HTML.Safe.to_iodata(PageHTML.login_page(conn, error: nil)))
  end

  def start(conn, %{"provider" => provider_key}) do
    case Auth.provider(provider_key) do
      nil ->
        unauthorized(conn, "Unknown identity provider.")

      provider ->
        state = random_token()
        verifier = random_token()
        challenge = pkce_challenge(verifier)
        redirect_uri = callback_url(provider.key)

        params =
          Map.merge(provider.authorize_params, %{
            "client_id" => provider.client_id,
            "code_challenge" => challenge,
            "code_challenge_method" => "S256",
            "redirect_uri" => redirect_uri,
            "response_type" => "code",
            "scope" => provider.scopes,
            "state" => state
          })

        conn
        |> put_session(:oauth_state, state)
        |> put_session(:oauth_verifier, verifier)
        |> put_session(:oauth_provider, provider.key)
        |> redirect(external: "#{provider.authorize_url}?#{URI.encode_query(params)}")
    end
  end

  def callback(conn, %{"provider" => provider_key, "code" => code, "state" => state}) do
    with provider when not is_nil(provider) <- Auth.provider(provider_key),
         ^provider_key <- get_session(conn, :oauth_provider),
         ^state <- get_session(conn, :oauth_state),
         {:ok, token} <- exchange_code(conn, provider, code),
         {:ok, user} <- fetch_user(provider, token),
         :ok <- check_domain(provider, user) do
      conn
      |> configure_session(renew: true)
      |> put_session(:current_user, user)
      |> delete_session(:oauth_state)
      |> delete_session(:oauth_verifier)
      |> delete_session(:oauth_provider)
      |> redirect(to: ~p"/")
    else
      {:error, :domain_not_allowed} ->
        unauthorized(conn, "Your account isn't from an allowed domain for this instance.")

      _ ->
        unauthorized(conn, "The login attempt could not be completed.")
    end
  end

  def callback(conn, %{"provider" => _}) do
    unauthorized(conn, "The login callback was missing required parameters.")
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/login")
  end

  defp callback_url(provider_key), do: url(~p"/auth/#{provider_key}/callback")

  defp check_domain(%{allowed_domains: []}, _user), do: :ok

  defp check_domain(%{allowed_domains: domains}, %{"email" => email}) when is_binary(email) do
    domain = email |> String.split("@", parts: 2) |> List.last() |> String.downcase()
    if domain in domains, do: :ok, else: {:error, :domain_not_allowed}
  end

  defp check_domain(_provider, _user), do: {:error, :domain_not_allowed}

  defp exchange_code(conn, provider, code) do
    form = [
      client_id: provider.client_id,
      code: code,
      code_verifier: get_session(conn, :oauth_verifier),
      grant_type: "authorization_code",
      redirect_uri: callback_url(provider.key)
    ]

    form =
      if provider.client_secret in [nil, ""] do
        form
      else
        Keyword.put(form, :client_secret, provider.client_secret)
      end

    case Req.post(provider.token_url, form: form, receive_timeout: 10_000) do
      {:ok, %{status: status, body: %{"access_token" => token}}} when status in 200..299 ->
        {:ok, token}

      _ ->
        :error
    end
  end

  defp fetch_user(provider, token) do
    if provider.userinfo_url in [nil, ""] do
      {:ok, %{"name" => "Authenticated user"}}
    else
      case Req.get(provider.userinfo_url, auth: {:bearer, token}, receive_timeout: 10_000) do
        {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
          {:ok,
           %{
             "email" => body["email"],
             "name" =>
               body["name"] || body["preferred_username"] || body["email"] || "Authenticated user"
           }}

        _ ->
          :error
      end
    end
  end

  defp unauthorized(conn, message) do
    conn
    |> put_status(:unauthorized)
    |> html(
      Phoenix.HTML.Safe.to_iodata(
        PageHTML.login_page(conn, error: message)
      )
    )
  end

  defp random_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp pkce_challenge(verifier) do
    :sha256
    |> :crypto.hash(verifier)
    |> Base.url_encode64(padding: false)
  end
end

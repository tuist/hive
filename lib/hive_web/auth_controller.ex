defmodule HiveWeb.AuthController do
  use HiveWeb, :controller

  alias Hive.Auth
  alias HiveWeb.PageHTML

  def new(conn, _params) do
    html(conn, Phoenix.HTML.Safe.to_iodata(PageHTML.login_page(conn, error: nil)))
  end

  def oidc(conn, _params) do
    if Auth.oidc_ready?() do
      state = random_token()
      verifier = random_token()
      challenge = pkce_challenge(verifier)
      redirect_uri = url(~p"/auth/oidc/callback")
      config = Auth.oidc_config()

      query =
        URI.encode_query(%{
          "client_id" => config.client_id,
          "code_challenge" => challenge,
          "code_challenge_method" => "S256",
          "redirect_uri" => redirect_uri,
          "response_type" => "code",
          "scope" => config.scopes,
          "state" => state
        })

      conn
      |> put_session(:oidc_state, state)
      |> put_session(:oidc_verifier, verifier)
      |> redirect(external: "#{config.authorize_url}?#{query}")
    else
      conn
      |> put_status(:service_unavailable)
      |> html(
        Phoenix.HTML.Safe.to_iodata(
          PageHTML.login_page(conn, error: "OIDC login is not configured.")
        )
      )
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    with ^state <- get_session(conn, :oidc_state),
         {:ok, token} <- exchange_code(conn, code),
         {:ok, user} <- fetch_user(token) do
      conn
      |> configure_session(renew: true)
      |> put_session(:current_user, user)
      |> delete_session(:oidc_state)
      |> delete_session(:oidc_verifier)
      |> redirect(to: ~p"/")
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> html(
          Phoenix.HTML.Safe.to_iodata(
            PageHTML.login_page(conn, error: "The login attempt could not be completed.")
          )
        )
    end
  end

  def callback(conn, _params) do
    conn
    |> put_status(:unauthorized)
    |> html(
      Phoenix.HTML.Safe.to_iodata(
        PageHTML.login_page(conn, error: "The login callback was missing required parameters.")
      )
    )
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/login")
  end

  defp exchange_code(conn, code) do
    config = Auth.oidc_config()

    form = [
      client_id: config.client_id,
      code: code,
      code_verifier: get_session(conn, :oidc_verifier),
      grant_type: "authorization_code",
      redirect_uri: url(~p"/auth/oidc/callback")
    ]

    form =
      if config.client_secret in [nil, ""] do
        form
      else
        Keyword.put(form, :client_secret, config.client_secret)
      end

    case Req.post(config.token_url, form: form, receive_timeout: 10_000) do
      {:ok, %{status: status, body: %{"access_token" => token}}} when status in 200..299 ->
        {:ok, token}

      _ ->
        :error
    end
  end

  defp fetch_user(token) do
    config = Auth.oidc_config()

    if config.userinfo_url in [nil, ""] do
      {:ok, %{"name" => "Authenticated user"}}
    else
      case Req.get(config.userinfo_url, auth: {:bearer, token}, receive_timeout: 10_000) do
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

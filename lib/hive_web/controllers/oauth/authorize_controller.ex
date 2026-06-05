defmodule HiveWeb.OAuth.AuthorizeController do
  @behaviour Boruta.Oauth.AuthorizeApplication

  use HiveWeb, :controller

  alias Boruta.Oauth
  alias Boruta.Oauth.AuthorizeApplication
  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.AuthorizationSuccess
  alias Boruta.Oauth.ResourceOwner
  alias Hive.Auth

  @max_state_length 10_000

  def authorize(conn, params) do
    validate_state_length!(params)

    case Auth.current_user(conn) do
      nil ->
        conn
        |> put_session(:user_return_to, current_path(conn))
        |> redirect(to: ~p"/login")
        |> halt()

      user ->
        Oauth.preauthorize(conn, resource_owner(user), __MODULE__)
    end
  end

  def approve(conn, %{"decision" => "approve"} = params) do
    validate_state_length!(params)

    case Auth.current_user(conn) do
      nil ->
        conn
        |> put_session(:user_return_to, current_path(conn))
        |> redirect(to: ~p"/login")
        |> halt()

      user ->
        Oauth.authorize(conn, resource_owner(user), __MODULE__)
    end
  end

  def approve(conn, _params) do
    conn
    |> put_status(:forbidden)
    |> html("OAuth authorization was denied.")
  end

  @impl AuthorizeApplication
  def authorize_success(conn, %AuthorizeResponse{} = response) do
    redirect(conn, external: AuthorizeResponse.redirect_to_url(response))
  end

  @impl AuthorizeApplication
  def authorize_error(conn, %Error{format: format} = error) when not is_nil(format) do
    redirect(conn, external: Error.redirect_to_url(error))
  end

  def authorize_error(conn, %Error{} = error) do
    conn
    |> put_status(error_status(error.status))
    |> json(%{error: to_string(error.error), error_description: error.error_description})
  end

  @impl AuthorizeApplication
  def preauthorize_success(conn, %AuthorizationSuccess{} = authorization) do
    conn
    |> put_resp_content_type("text/html")
    |> html(consent_page(conn, authorization))
  end

  @impl AuthorizeApplication
  def preauthorize_error(conn, %Error{} = error), do: authorize_error(conn, error)

  defp error_status(:bad_request), do: 400
  defp error_status(:unauthorized), do: 401
  defp error_status(:internal_server_error), do: 500
  defp error_status(_status), do: 400

  defp validate_state_length!(%{"state" => state}) when byte_size(state) > @max_state_length do
    raise Plug.BadRequestError,
      message: "The state parameter must not exceed #{@max_state_length} characters."
  end

  defp validate_state_length!(_params), do: :ok

  defp resource_owner(user), do: %ResourceOwner{sub: user.id, username: user.email}

  defp consent_page(conn, authorization) do
    client_name = authorization.client.name || "OAuth client"
    redirect_uri = authorization.redirect_uri || ""
    scope = authorization.scope || ""

    """
    <main id="oauth-consent">
      <h1>Authorize #{html_escape(client_name)}</h1>
      <p>Allow this client to access Hive MCP as #{html_escape(authorization.resource_owner.username)}?</p>
      <dl>
        <dt>Redirect URI</dt>
        <dd>#{html_escape(redirect_uri)}</dd>
        <dt>Scopes</dt>
        <dd>#{html_escape(scope)}</dd>
      </dl>
      <form method="post" action="#{html_escape(current_path(conn))}">
        <input type="hidden" name="_csrf_token" value="#{html_escape(Plug.CSRFProtection.get_csrf_token())}" />
        <button type="submit" name="decision" value="approve">Allow</button>
        <button type="submit" name="decision" value="deny">Deny</button>
      </form>
    </main>
    """
  end

  defp html_escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end

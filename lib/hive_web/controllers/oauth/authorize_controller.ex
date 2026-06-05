defmodule HiveWeb.OAuth.AuthorizeController do
  @behaviour Boruta.Oauth.AuthorizeApplication

  use HiveWeb, :controller

  alias Boruta.Oauth
  alias Boruta.Oauth.AuthorizeApplication
  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
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
        Oauth.authorize(conn, %ResourceOwner{sub: user.id, username: user.email}, __MODULE__)
    end
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
  def preauthorize_success(_conn, _response), do: :ok

  @impl AuthorizeApplication
  def preauthorize_error(_conn, _response), do: :ok

  defp error_status(:bad_request), do: 400
  defp error_status(:unauthorized), do: 401
  defp error_status(:internal_server_error), do: 500
  defp error_status(_status), do: 400

  defp validate_state_length!(%{"state" => state}) when byte_size(state) > @max_state_length do
    raise Plug.BadRequestError,
      message: "The state parameter must not exceed #{@max_state_length} characters."
  end

  defp validate_state_length!(_params), do: :ok
end

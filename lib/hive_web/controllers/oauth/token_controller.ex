defmodule HiveWeb.OAuth.TokenController do
  @behaviour Boruta.Oauth.TokenApplication

  use HiveWeb, :controller

  alias Boruta.Oauth.Error
  alias Boruta.Oauth.TokenApplication
  alias Boruta.Oauth.TokenResponse

  def token(conn, _params) do
    Boruta.Oauth.token(conn, __MODULE__)
  end

  @impl TokenApplication
  def token_success(conn, %TokenResponse{} = response) do
    token_data =
      %{
        token_type: response.token_type,
        access_token: response.access_token,
        expires_in: response.expires_in,
        refresh_token: response.refresh_token,
        id_token: response.id_token
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> json(token_data)
  end

  @impl TokenApplication
  def token_error(conn, %Error{status: status, error: error, error_description: error_description}) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: error_description})
  end
end

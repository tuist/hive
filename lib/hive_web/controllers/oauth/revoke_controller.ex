defmodule HiveWeb.OAuth.RevokeController do
  @behaviour Boruta.Oauth.RevokeApplication

  use HiveWeb, :controller

  alias Boruta.Oauth.Error

  def revoke(conn, _params) do
    Boruta.Oauth.revoke(conn, __MODULE__)
  end

  @impl Boruta.Oauth.RevokeApplication
  def revoke_success(conn), do: send_resp(conn, :ok, "")

  @impl Boruta.Oauth.RevokeApplication
  def revoke_error(conn, %Error{
        status: status,
        error: error,
        error_description: error_description
      }) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: error_description})
  end
end

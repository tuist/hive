defmodule HiveWeb.Plugs.RequireAuthenticated do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn

  alias Hive.Auth
  use HiveWeb, :verified_routes

  def init(opts), do: opts

  def call(conn, _opts) do
    if Auth.private?() and is_nil(Auth.current_user(conn)) do
      conn
      |> put_session(:user_return_to, requested_path(conn))
      |> redirect(to: ~p"/login")
      |> halt()
    else
      conn
    end
  end

  defp requested_path(%{query_string: ""} = conn), do: conn.request_path
  defp requested_path(conn), do: conn.request_path <> "?" <> conn.query_string
end

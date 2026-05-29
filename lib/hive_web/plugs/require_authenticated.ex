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
      |> redirect(to: ~p"/login")
      |> halt()
    else
      conn
    end
  end
end

defmodule HiveWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias Hive.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> redirect(to: "/login")
        |> halt()

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            conn
            |> configure_session(drop: true)
            |> redirect(to: "/login")
            |> halt()

          user ->
            assign(conn, :current_user, user)
        end
    end
  end
end

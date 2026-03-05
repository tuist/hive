defmodule HiveWeb.LayoutLive do
  @moduledoc """
  Assigns shared data for authenticated dashboard LiveViews.
  """

  use HiveWeb, :live_view

  alias Hive.Accounts

  def on_mount(:default, _params, session, socket) do
    user_id = session["user_id"]

    if user_id do
      user = Accounts.get_user(user_id)

      {:cont,
       socket
       |> assign(:current_user, user)
       |> assign(:current_path, "/")
       |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
         %{path: current_path} = URI.parse(url)
         {:cont, assign(socket, :current_path, current_path)}
       end)}
    else
      {:halt, redirect(socket, to: ~p"/login")}
    end
  end
end

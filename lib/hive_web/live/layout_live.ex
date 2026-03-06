defmodule HiveWeb.LayoutLive do
  @moduledoc """
  Assigns shared data for dashboard LiveViews.

  When the instance is public, unauthenticated users can view read-only pages.
  Write operations require authentication and are guarded by `Hive.Policy`.
  """

  use HiveWeb, :live_view

  alias Hive.Accounts

  def on_mount(:default, _params, session, socket) do
    user = load_user(session)
    public? = Application.get_env(:hive, :public, false)

    cond do
      user != nil ->
        {:cont, assign_user(socket, user)}

      public? ->
        {:cont, assign_guest(socket)}

      true ->
        {:halt, redirect(socket, to: ~p"/login")}
    end
  end

  defp load_user(%{"user_id" => user_id}) when is_binary(user_id), do: Accounts.get_user(user_id)
  defp load_user(_session), do: nil

  defp assign_user(socket, user) do
    socket
    |> assign(:current_user, user)
    |> assign(:current_path, "/")
    |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
      %{path: current_path} = URI.parse(url)
      {:cont, assign(socket, :current_path, current_path)}
    end)
  end

  defp assign_guest(socket) do
    socket
    |> assign(:current_user, nil)
    |> assign(:current_path, "/")
    |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
      %{path: current_path} = URI.parse(url)
      {:cont, assign(socket, :current_path, current_path)}
    end)
  end
end

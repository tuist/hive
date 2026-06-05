defmodule HiveWeb.DashboardLive.Hooks do
  @moduledoc """
  on_mount hook shared by LiveViews rendered inside the dashboard layout.
  It loads the current user from the session and assigns the chrome that
  `Layouts.dashboard` needs, plus a handle_params hook that tracks the
  current path for the sidebar's active state.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Forage

  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> assign_chrome(session)
      |> attach_hook(:dashboard_current_path, :handle_params, &put_current_path/3)

    {:cont, socket}
  end

  @doc """
  Assigns the dashboard chrome (current user plus the values
  `Layouts.dashboard` needs) from the LiveView session.
  """
  def assign_chrome(socket, session) do
    user = Accounts.get_user(session["user_id"])
    user_name = (user && user.email) || "Guest"

    socket
    |> assign(:current_user, user)
    |> assign(:product_name, Auth.product_name())
    |> assign(:user_name, user_name)
    |> assign(:user_email, user && user.email)
    |> assign(:avatar_color, if(user, do: "purple", else: "gray"))
    |> assign(:auth_enabled?, Auth.private?())
    |> assign(:signed_in?, not is_nil(user))
    |> assign(:settings_enabled?, Auth.member?(user))
    |> assign(:csrf_token, Plug.CSRFProtection.get_csrf_token())
    |> assign(:forage_sources, Forage.visible_sources(user))
    |> assign(:current_path, "/")
  end

  @doc "handle_params hook that tracks the current path for the sidebar."
  def put_current_path(_params, uri, socket) do
    {:cont, assign(socket, :current_path, URI.parse(uri).path)}
  end
end

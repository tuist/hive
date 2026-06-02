defmodule HiveWeb.ForageLive.Hooks do
  @moduledoc """
  on_mount hook shared by the forage LiveViews. Loads the current user
  from the session and assigns the chrome that `Layouts.dashboard`
  needs, plus a handle_params hook that tracks the current path for the
  sidebar's active state.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Forage

  def on_mount(:default, _params, session, socket) do
    user = Accounts.get_user(session["user_id"])
    user_name = (user && user.email) || "Guest"

    socket =
      socket
      |> assign(:current_user, user)
      |> assign(:product_name, Auth.product_name())
      |> assign(:user_name, user_name)
      |> assign(:user_email, user && user.email)
      |> assign(:avatar_color, if(user, do: "purple", else: "gray"))
      |> assign(:auth_enabled?, Auth.private?())
      |> assign(:signed_in?, not is_nil(user))
      |> assign(:csrf_token, Plug.CSRFProtection.get_csrf_token())
      |> assign(:forage_sources, Forage.visible_sources(user))
      |> assign(:current_path, "/")
      |> attach_hook(:forage_current_path, :handle_params, &put_current_path/3)

    {:cont, socket}
  end

  defp put_current_path(_params, uri, socket) do
    {:cont, assign(socket, :current_path, URI.parse(uri).path)}
  end
end

defmodule HiveWeb.ForageLive.FeatureRequests do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Forage
  alias HiveWeb.ForageComponents
  alias HiveWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    source = Forage.get_source!(:feature_requests)

    {:ok,
     socket
     |> assign(:page_title, "Feature requests · #{socket.assigns.product_name}")
     |> assign(:source, source)
     |> assign(:feature_requests, Forage.list_feature_requests())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      product_name={@product_name}
      user_name={@user_name}
      user_email={@user_email}
      avatar_color={@avatar_color}
      auth_enabled?={@auth_enabled?}
      signed_in?={@signed_in?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
    >
      <ForageComponents.feature_requests
        source={@source}
        feature_requests={@feature_requests}
        signed_in?={@signed_in?}
      />
    </Layouts.dashboard>
    """
  end
end

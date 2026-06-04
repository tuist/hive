defmodule HiveWeb.ForageLive.Placeholder do
  @moduledoc """
  Renders a forage source that has no ingestion yet (bug reports,
  feedback, grafana alerts). The source is selected by the route's
  live_action; access is gated so organization-only sources stay hidden
  from non-members.
  """

  use HiveWeb, :live_view

  alias Hive.Forage
  alias HiveWeb.ForageComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, _uri, socket) do
    source = Forage.get_source!(socket.assigns.live_action)

    if Forage.can_access?(source, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:page_title, "#{source.label} · #{socket.assigns.product_name}")
       |> assign(OpenGraph.assigns(OpenGraph.forage_source_page(source)))
       |> assign(:source, source)}
    else
      {:noreply, redirect(socket, to: ~p"/forage/feature-requests")}
    end
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
      <ForageComponents.placeholder source={@source} signed_in?={@signed_in?} />
    </Layouts.dashboard>
    """
  end
end

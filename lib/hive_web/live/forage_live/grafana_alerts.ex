defmodule HiveWeb.ForageLive.GrafanaAlerts do
  @moduledoc """
  Renders Grafana alerts ingested via meadow webhooks. Visibility is
  organization-only, gated through the forage policy.
  """

  use HiveWeb, :live_view

  alias Hive.Forage
  alias HiveWeb.ForageComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description: "Operational signals visible only to organization members.",
      eyebrow: "Forage",
      highlights: ["Organization visible", "Read-only signals", "Forage source"],
      id: "forage-grafana-alerts",
      path: "/forage/grafana-alerts",
      title: "Grafana alerts"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    source = Forage.get_source!(:grafana_alerts)

    if Forage.can_access?(source, socket.assigns.current_user) do
      alerts = Forage.list_grafana_alerts()

      {:ok,
       socket
       |> assign(:page_title, "Grafana alerts · #{socket.assigns.product_name}")
       |> assign(OpenGraph.assigns(open_graph()))
       |> assign(:source, source)
       |> assign(:alerts, alerts)}
    else
      {:ok, redirect(socket, to: ~p"/forage/feature-requests")}
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
      <ForageComponents.grafana_alerts source={@source} alerts={@alerts} />
    </Layouts.dashboard>
    """
  end
end

defmodule HiveWeb.ForageLive.GrafanaAlerts do
  @moduledoc """
  Renders Grafana alerts ingested via project webhooks. Visibility is
  organization-only, gated through the forage policy.
  """

  use HiveWeb, :live_view

  alias Hive.Forage
  alias HiveWeb.ForageComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description:
        dgettext("dashboard_forage", "Operational signals visible only to organization members."),
      section_label: dgettext("dashboard_forage", "Forage"),
      highlights: [
        dgettext("dashboard_forage", "Organization visible"),
        dgettext("dashboard_forage", "Read-only signals"),
        dgettext("dashboard_forage", "Forage source")
      ],
      id: "forage-grafana-alerts",
      path: "/forage/grafana-alerts",
      title: dgettext("dashboard_forage", "Grafana alerts")
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    source = Forage.get_source!(:grafana_alerts)

    if Forage.can_access?(source, socket.assigns.current_user) do
      alerts = Forage.list_grafana_alerts()

      {:ok,
       socket
       |> assign(
         :page_title,
         dgettext("dashboard_forage", "Grafana alerts · %{product}",
           product: socket.assigns.product_name
         )
       )
       |> assign(OpenGraph.assigns(open_graph()))
       |> assign(:atom_feed, %{
         title: dgettext("dashboard_forage", "Hive · Grafana alerts"),
         atom_href: "/forage/grafana-alerts/atom.xml",
         rss_href: "/forage/grafana-alerts/rss.xml"
       })
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
      flash={@flash}
      product_name={@product_name}
      user_name={@user_name}
      user_email={@user_email}
      avatar_color={@avatar_color}
      auth_enabled?={@auth_enabled?}
      signed_in?={@signed_in?}
      admin?={@admin?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
      specs_have_new_activity?={@specs_have_new_activity?}
    >
      <ForageComponents.grafana_alerts source={@source} alerts={@alerts} />
    </Layouts.dashboard>
    """
  end
end

defmodule HiveWeb.ForageLive.FeatureRequests do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Forage
  alias Hive.Specs
  alias HiveWeb.ForageComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph(feature_requests) do
    stats = feature_request_stats(feature_requests)

    %{
      description: "Public domain ideas submitted by authenticated users.",
      section_label: "Forage",
      highlights: [
        "#{stats.total} total requests",
        "#{stats.open} open",
        "#{stats.contributors} contributors"
      ],
      id: "forage-feature-requests",
      path: "/forage/feature-requests",
      title: "Feature requests"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    source = Forage.get_source!(:feature_requests)
    feature_requests = Forage.list_feature_requests()

    {:ok,
     socket
     |> assign(:page_title, "Feature requests · #{socket.assigns.product_name}")
     |> assign(OpenGraph.assigns(open_graph(feature_requests)))
     |> assign(:atom_feed, %{
       title: "Hive · Feature requests",
       atom_href: "/forage/feature-requests/atom.xml",
       rss_href: "/forage/feature-requests/rss.xml"
     })
     |> assign(:source, source)
     |> assign(:feature_requests, feature_requests)
     |> assign(:can_create_spec?, Specs.can_create?(socket.assigns.current_user))}
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
      admin?={@admin?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
      specs_have_new_activity?={@specs_have_new_activity?}
    >
      <ForageComponents.feature_requests
        source={@source}
        feature_requests={@feature_requests}
        signed_in?={@signed_in?}
        can_create_spec?={@can_create_spec?}
      />
    </Layouts.dashboard>
    """
  end

  defp feature_request_stats(feature_requests) do
    %{
      total: length(feature_requests),
      open: Enum.count(feature_requests, &(&1.status == :open)),
      contributors:
        feature_requests
        |> Enum.map(& &1.user_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length()
    }
  end
end

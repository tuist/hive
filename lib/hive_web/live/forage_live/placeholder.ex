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

  def open_graph(source) do
    %{
      description: source.description,
      section_label: "Forage",
      highlights: source_highlights(source),
      id: "forage-#{open_graph_slug(source)}",
      path: source.path,
      title: source.label
    }
  end

  def open_graph_slug(source) do
    source.id
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, _uri, socket) do
    source = Forage.get_source!(socket.assigns.live_action)

    if Forage.can_access?(source, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:page_title, "#{source.label} · #{socket.assigns.product_name}")
       |> assign(OpenGraph.assigns(open_graph(source)))
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
      admin?={@admin?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
      specs_have_new_activity?={@specs_have_new_activity?}
    >
      <ForageComponents.placeholder source={@source} signed_in?={@signed_in?} />
    </Layouts.dashboard>
    """
  end

  defp source_highlights(source) do
    [
      source_visibility(source.visibility),
      if(source.creatable?, do: "Contributor submissions", else: "Read-only signals"),
      "Forage source"
    ]
  end

  defp source_visibility(:organization), do: "Organization visible"
  defp source_visibility(_visibility), do: "Public source"
end

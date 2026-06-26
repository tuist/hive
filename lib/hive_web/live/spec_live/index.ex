defmodule HiveWeb.SpecLive.Index do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Specs
  alias Hive.Specs.Spec
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.SpecComponents
  alias Noora.Filter.Operations

  def open_graph(specs) do
    %{
      description:
        dgettext("dashboard_specs", "Editable proposals that shape forage into buildable work."),
      section_label: dgettext("dashboard_specs", "Specs"),
      highlights: [
        dgettext("dashboard_specs", "%{count} specs", count: length(specs)),
        dgettext("dashboard_specs", "%{count} drafts",
          count: Enum.count(specs, &(&1.status == :draft))
        ),
        dgettext("dashboard_specs", "%{count} shipped",
          count: Enum.count(specs, &(&1.status == :shipped))
        )
      ],
      id: "specs",
      path: "/specs",
      title: dgettext("dashboard_specs", "Specs")
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       :page_title,
       dgettext("dashboard_specs", "Specs · %{product}", product: socket.assigns.product_name)
     )
     |> assign(:available_filters, available_filters())
     |> assign(:active_filters, [])
     |> assign(:uri, URI.parse("/specs"))
     |> assign(OpenGraph.assigns(open_graph([])))
     |> assign(:atom_feed, %{
       title: dgettext("dashboard_specs", "Hive · Specs"),
       atom_href: "/specs/atom.xml",
       rss_href: "/specs/rss.xml"
     })
     |> assign(:specs, [])
     |> assign(:can_create?, Specs.can_create?(socket.assigns.current_user))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    uri = URI.parse(uri)

    active_filters =
      Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    specs =
      Specs.list_specs(
        status: status_filter(active_filters),
        user: socket.assigns.current_user
      )

    {:noreply,
     socket
     |> assign(:uri, %{uri | query: URI.encode_query(params)})
     |> assign(:active_filters, active_filters)
     |> assign(:specs, specs)
     |> assign(OpenGraph.assigns(open_graph(specs)))}
  end

  @impl true
  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    params = Operations.add_filter_to_query(filter_id, socket)
    {:noreply, push_patch(socket, to: ~p"/specs?#{params}")}
  end

  @impl true
  def handle_event("update_filter", params, socket) do
    params = Operations.update_filters_in_query(params, socket)
    {:noreply, push_patch(socket, to: ~p"/specs?#{params}")}
  end

  defp available_filters do
    [
      %Noora.Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_specs", "Status"),
        type: :option,
        options: Spec.statuses(),
        options_display_names: Map.new(Spec.statuses(), &{&1, status_label(&1)}),
        operator: :==,
        value: :draft
      }
    ]
  end

  defp status_filter(active_filters) do
    active_filters
    |> Enum.find(&(&1.id == "status"))
    |> case do
      %{operator: :==, value: status} when is_atom(status) -> status
      %{operator: :!=, value: status} when is_atom(status) -> {:not, status}
      _filter -> nil
    end
  end

  defp status_label(:draft), do: dgettext("dashboard_specs", "Draft")
  defp status_label(:proposed), do: dgettext("dashboard_specs", "Proposed")
  defp status_label(:approved), do: dgettext("dashboard_specs", "Approved")
  defp status_label(:paused), do: dgettext("dashboard_specs", "Paused")
  defp status_label(:rejected), do: dgettext("dashboard_specs", "Rejected")
  defp status_label(:in_progress), do: dgettext("dashboard_specs", "In progress")
  defp status_label(:shipped), do: dgettext("dashboard_specs", "Shipped")
  defp status_label(:archived), do: dgettext("dashboard_specs", "Archived")

  defp status_label(status),
    do: status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

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
      <SpecComponents.index
        specs={@specs}
        can_create?={@can_create?}
        available_filters={@available_filters}
        active_filters={@active_filters}
      />
    </Layouts.dashboard>
    """
  end
end

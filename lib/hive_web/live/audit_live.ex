defmodule HiveWeb.AuditLive do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  import Noora.Filter

  alias Hive.Audit
  alias Hive.Audit.Activity
  alias Hive.Audit.Policy
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.Utilities.Query
  alias Noora.Filter

  @page_size 10

  def open_graph do
    %{
      description:
        "Trace Hive activity across the dashboard, MCP, webhooks, jobs, and system paths.",
      eyebrow: "Audit",
      highlights: [],
      id: "audit",
      path: "/audit",
      title: "Audit"
    }
  end

  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    if Policy.authorize?(:audit_activity_read, user, nil) do
      {:ok,
       socket
       |> assign(:page_title, "Audit · #{socket.assigns.product_name}")
       |> assign(:available_filters, [])
       |> assign(OpenGraph.assigns(open_graph()))}
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have access to the audit trail.")
       |> push_navigate(to: ~p"/")}
    end
  end

  def handle_params(params, uri, socket) do
    available_filters = define_filters()
    query_params = Query.query_params(uri)

    page = Query.parse_page(params["page"])
    query = params["q"] || ""
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    {activities, meta} =
      Audit.list_activities(audit_list_opts(query, active_filters, page))

    socket =
      socket
      |> assign(:uri, uri_from_query_params(query_params))
      |> assign(:activities, activities)
      |> assign(:activities_empty?, activities == [])
      |> assign(:activities_meta, meta)
      |> assign(:available_filters, available_filters)
      |> assign(:active_filters, active_filters)
      |> assign(:query, query)
      |> assign(:search_form, to_form(%{"query" => query}, as: :search))

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/audit?#{audit_query_params(query, socket.assigns.active_filters)}",
       replace: true
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Filter.Operations.add_filter_to_query(filter_id, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/audit?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Filter.Operations.update_filters_in_query(params, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/audit?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

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
    >
      <section id="audit">
        <div data-part="header">
          <div data-part="title-group">
            <.badge label="Audit" color="information" style="light-fill" />
            <h1>Audit</h1>
            <p>Trace Hive activity across the dashboard, MCP, webhooks, jobs, and system paths.</p>
          </div>
        </div>

        <.card title="Activity" icon="history">
          <.card_section>
            <div data-part="table-toolbar">
              <.filter_dropdown
                id="audit-filter"
                label="Filter"
                available_filters={@available_filters}
                active_filters={@active_filters}
                on_select="add_filter"
              />

              <div data-part="search">
                <.form
                  id="audit-search-form"
                  for={@search_form}
                  phx-change="search"
                  phx-submit="search"
                >
                  <.text_input
                    id="audit-search"
                    field={@search_form[:query]}
                    type="search"
                    show_suffix={false}
                    placeholder="Search actor, action, target, or metadata..."
                  />
                </.form>
              </div>
            </div>

            <div :if={@active_filters != []} data-part="active-filters">
              <.active_filter :for={filter <- @active_filters} filter={filter} />
            </div>

            <.table id="audit-table" rows={@activities}>
              <:col :let={activity} label="Time">
                <.text_cell
                  label={format_datetime(activity.occurred_at)}
                  sublabel={format_date(activity.occurred_at)}
                />
              </:col>
              <:col :let={activity} label="Actor">
                <.text_and_description_cell
                  label={Audit.actor_label(activity)}
                  description={actor_description(activity)}
                />
              </:col>
              <:col :let={activity} label="Kind">
                <.badge_cell
                  label={actor_kind_label(activity.actor_kind)}
                  color={actor_kind_badge_color(activity.actor_kind)}
                  style="light-fill"
                />
              </:col>
              <:col :let={activity} label="Interface">
                <.badge_cell
                  label={interface_label(activity.interface)}
                  color={interface_badge_color(activity.interface)}
                  style="light-fill"
                />
              </:col>
              <:col :let={activity} label="Action">
                <.text_cell label={action_label(activity.action)} sublabel={activity.action} />
              </:col>
              <:col :let={activity} label="Target">
                <.link
                  :if={activity_path(activity)}
                  navigate={activity_path(activity)}
                  data-part="target-link"
                >
                  <.text_and_description_cell
                    label={activity.target_label || activity.target_id || "-"}
                    description={target_description(activity)}
                  />
                </.link>
                <.text_and_description_cell
                  :if={!activity_path(activity)}
                  label={activity.target_label || activity.target_id || "-"}
                  description={target_description(activity)}
                />
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="history"
                  title="No activity found"
                  subtitle="Adjust the filters or wait for new activity to be recorded."
                />
              </:empty_state>
            </.table>

            <div :if={@activities_meta.total_pages > 1} data-part="pagination">
              <.button
                variant="secondary"
                label="Prev"
                disabled={@activities_meta.current_page <= 1}
                patch={page_link(@uri, max(1, @activities_meta.current_page - 1))}
              >
                <:icon_left><.chevron_left /></:icon_left>
              </.button>
              <.button
                variant="secondary"
                label="Next"
                disabled={@activities_meta.current_page >= @activities_meta.total_pages}
                patch={
                  page_link(
                    @uri,
                    min(@activities_meta.total_pages, @activities_meta.current_page + 1)
                  )
                }
              >
                <:icon_right><.chevron_right /></:icon_right>
              </.button>
            </div>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  defp page_link(uri, page) do
    "?" <> Query.put(uri.query, "page", Integer.to_string(page))
  end

  defp audit_query_params(query, active_filters) do
    active_filters
    |> Filter.Operations.encode_filters_to_query()
    |> Query.put_present("q", Query.present_string(query))
  end

  defp audit_list_opts(query, active_filters, page) do
    [page: page, page_size: @page_size, query: Query.present_string(query)]
    |> put_active_filter(active_filters, "interface", :interface, :exclude_interface)
    |> put_active_filter(active_filters, "action", :action, :exclude_action)
    |> put_active_filter(active_filters, "actor_kind", :actor_kind, :exclude_actor_kind)
    |> put_active_filter(active_filters, "target_type", :target_type, :exclude_target_type)
  end

  defp put_active_filter(opts, active_filters, filter_id, include_key, exclude_key) do
    case Enum.find(active_filters, &(&1.id == filter_id)) do
      %{operator: :==, value: value} -> put_option(opts, include_key, Query.present_string(value))
      %{operator: :!=, value: value} -> put_option(opts, exclude_key, Query.present_string(value))
      _filter -> opts
    end
  end

  defp put_option(opts, _key, nil), do: opts
  defp put_option(opts, key, value), do: Keyword.put(opts, key, value)

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp uri_from_query_params(params) do
    case URI.encode_query(params) do
      "" -> URI.parse("")
      query -> URI.parse("?" <> query)
    end
  end

  defp define_filters do
    options = Audit.filter_options()

    [
      option_filter("interface", "Interface", options.interfaces, &interface_label/1,
        searchable: true
      ),
      option_filter("actor_kind", "Actor kind", options.actor_kinds, &actor_kind_label/1,
        searchable: false
      ),
      option_filter("action", "Action", options.actions, &action_label/1, searchable: true),
      option_filter("target_type", "Target", options.target_types, &target_label/1,
        searchable: true
      )
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp option_filter(id, display_name, options, formatter, opts) do
    options =
      options
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    %Filter.Filter{
      id: id,
      display_name: display_name,
      type: :option,
      options: options,
      options_display_names: Map.new(options, &{&1, formatter.(&1)}),
      operator: :==,
      searchable: Keyword.get(opts, :searchable, false),
      value: nil
    }
  end

  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M:%S UTC")
  defp format_datetime(_datetime), do: "-"

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_date(_datetime), do: "-"

  defp actor_description(%Activity{actor_kind: "agent", metadata: %{"agent_model" => model}})
       when is_binary(model) and model != "",
       do: model

  defp actor_description(%Activity{actor_kind: "agent"}), do: "Agent"

  defp actor_description(%Activity{actor_kind: "system"}), do: "Automated"

  defp actor_description(%Activity{actor_email: email}) when is_binary(email) and email != "",
    do: email

  defp actor_description(%Activity{actor_role: role}) when is_binary(role) and role != "",
    do: interface_label(role)

  defp actor_description(_activity), do: "No actor"

  defp actor_kind_label("user"), do: "User"
  defp actor_kind_label("agent"), do: "Agent"
  defp actor_kind_label("system"), do: "System"
  defp actor_kind_label(_kind), do: "-"

  defp actor_kind_badge_color("user"), do: "information"
  defp actor_kind_badge_color("agent"), do: "focus"
  defp actor_kind_badge_color("system"), do: "neutral"
  defp actor_kind_badge_color(_kind), do: "neutral"

  defp target_description(%Activity{target_type: nil}), do: "-"

  defp target_description(%Activity{target_type: type, target_id: id})
       when is_binary(id) and id != "" do
    "#{target_label(type)} · #{id}"
  end

  defp target_description(%Activity{target_type: type}), do: target_label(type)

  defp activity_path(%Activity{} = activity),
    do: Audit.resource_path(activity.target_type, activity.target_id, activity.metadata)

  defp action_label(action) when is_binary(action) do
    action
    |> String.replace([".", "_"], " ")
    |> String.capitalize()
  end

  defp action_label(_action), do: "-"

  defp target_label(target) when is_binary(target) do
    target
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp target_label(_target), do: "-"

  defp interface_label("mcp"), do: "MCP"

  defp interface_label(interface) when is_binary(interface) do
    interface
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp interface_label(_interface), do: "-"

  defp interface_badge_color("dashboard"), do: "information"
  defp interface_badge_color("mcp"), do: "focus"
  defp interface_badge_color("webhook"), do: "success"
  defp interface_badge_color("worker"), do: "warning"
  defp interface_badge_color(_interface), do: "neutral"
end

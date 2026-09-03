defmodule HiveWeb.ErrorsLive.Index do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  import Noora.Filter

  alias Hive.Errors
  alias Hive.Errors.Issue
  alias Hive.Errors.Policy
  alias Hive.Projects
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.Utilities.Query
  alias Noora.Filter

  @page_size 25

  def open_graph do
    %{
      description:
        dgettext(
          "dashboard_errors",
          "Unhandled exceptions captured from your applications and from Hive itself."
        ),
      section_label: dgettext("dashboard_errors", "Errors"),
      highlights: [
        dgettext("dashboard_errors", "Sentry-compatible"),
        dgettext("dashboard_errors", "Private")
      ],
      id: "errors",
      path: "/errors",
      title: dgettext("dashboard_errors", "Errors")
    }
  end

  def slack_unfurl(_uri, _params), do: :skip

  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    if Policy.authorize?(:error_issue_read, user, nil) do
      {:ok,
       socket
       |> assign(
         :page_title,
         dgettext("dashboard_errors", "Errors · %{product}", product: socket.assigns.product_name)
       )
       |> assign(:available_filters, [])
       |> assign(OpenGraph.assigns(open_graph()))}
    else
      {:ok, redirect_to_home(socket)}
    end
  end

  def handle_params(params, uri, socket) do
    available_filters = define_filters()
    query_params = Query.query_params(uri)

    page = Query.parse_page(params["page"])
    query = params["q"] || ""
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    {issues, meta} = Errors.paginate_issues(list_opts(query, active_filters, page))

    socket =
      socket
      |> assign(:uri, uri_from_query_params(query_params))
      |> assign(:issues, issues)
      |> assign(:issues_meta, meta)
      |> assign(:available_filters, available_filters)
      |> assign(:active_filters, active_filters)
      |> assign(:query, query)
      |> assign(:search_form, to_form(%{"query" => query}, as: :search))

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/errors?#{query_params(query, socket.assigns.active_filters)}",
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
     |> push_patch(to: ~p"/errors?#{updated_params}")
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
     |> push_patch(to: ~p"/errors?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

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
      member?={@member?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
      specs_have_new_activity?={@specs_have_new_activity?}
    >
      <section id="errors">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{dgettext("dashboard_errors", "Errors")}</h1>
            <p>
              {dgettext(
                "dashboard_errors",
                "Unhandled exceptions captured from your applications and from Hive itself."
              )}
            </p>
          </div>
        </div>

        <.card title={dgettext("dashboard_errors", "Issues")} icon="alert_circle">
          <.card_section>
            <div data-part="table-toolbar">
              <.filter_dropdown
                id="errors-filter"
                label={dgettext("dashboard_errors", "Filter")}
                available_filters={@available_filters}
                active_filters={@active_filters}
                on_select="add_filter"
              />

              <div data-part="search">
                <.form
                  id="errors-search-form"
                  for={@search_form}
                  phx-change="search"
                  phx-submit="search"
                >
                  <.text_input
                    id="errors-search"
                    field={@search_form[:query]}
                    type="search"
                    show_suffix={false}
                    placeholder={dgettext("dashboard_errors", "Search title or culprit...")}
                  />
                </.form>
              </div>
            </div>

            <div :if={@active_filters != []} data-part="active-filters">
              <.active_filter :for={filter <- @active_filters} filter={filter} />
            </div>

            <.table id="errors-table" rows={@issues}>
              <:col :let={issue} label={dgettext("dashboard_errors", "Issue")}>
                <.link navigate={~p"/errors/#{issue.id}"} data-part="issue-link">
                  <.text_and_description_cell
                    label={issue.title}
                    description={issue.culprit || dgettext("dashboard_errors", "No location")}
                  />
                </.link>
              </:col>
              <:col :let={issue} label={dgettext("dashboard_errors", "Project")}>
                <.text_cell label={project_name(issue)} />
              </:col>
              <:col :let={issue} label={dgettext("dashboard_errors", "Level")}>
                <.badge_cell
                  label={level_label(issue.level)}
                  color={level_color(issue.level)}
                  style="light-fill"
                />
              </:col>
              <:col :let={issue} label={dgettext("dashboard_errors", "Status")}>
                <.badge_cell
                  label={status_label(issue.status)}
                  color={status_color(issue.status)}
                  style="light-fill"
                />
              </:col>
              <:col :let={issue} label={dgettext("dashboard_errors", "Events")}>
                <.text_cell label={Integer.to_string(issue.event_count)} />
              </:col>
              <:col :let={issue} label={dgettext("dashboard_errors", "Last seen")}>
                <.text_cell
                  label={format_datetime(issue.last_seen)}
                  sublabel={format_date(issue.last_seen)}
                />
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="alert_circle"
                  title={dgettext("dashboard_errors", "No issues found")}
                  subtitle={empty_subtitle(assigns)}
                />
              </:empty_state>
            </.table>

            <div :if={@issues_meta.total_pages > 1} data-part="pagination">
              <.button
                variant="secondary"
                label={dgettext("dashboard_errors", "Prev")}
                disabled={@issues_meta.current_page <= 1}
                patch={page_link(@uri, max(1, @issues_meta.current_page - 1))}
              >
                <:icon_left><.chevron_left /></:icon_left>
              </.button>
              <.button
                variant="secondary"
                label={dgettext("dashboard_errors", "Next")}
                disabled={@issues_meta.current_page >= @issues_meta.total_pages}
                patch={
                  page_link(
                    @uri,
                    min(@issues_meta.total_pages, @issues_meta.current_page + 1)
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

  defp empty_subtitle(%{query: q, active_filters: filters})
       when q != "" or filters != [],
       do: dgettext("dashboard_errors", "Adjust your search or filters to see more issues.")

  defp empty_subtitle(_assigns),
    do:
      dgettext(
        "dashboard_errors",
        "Send events to POST /api/<project_id>/envelope/ to start recording issues."
      )

  defp redirect_to_home(socket) do
    socket
    |> put_flash(
      :error,
      dgettext("dashboard_errors", "You do not have access to errors.")
    )
    |> push_navigate(to: ~p"/")
  end

  defp page_link(uri, page) do
    "?" <> Query.put(uri.query, "page", Integer.to_string(page))
  end

  defp query_params(query, active_filters) do
    active_filters
    |> Filter.Operations.encode_filters_to_query()
    |> Query.put_present("q", Query.present_string(query))
  end

  defp list_opts(query, active_filters, page) do
    [page: page, page_size: @page_size, search: Query.present_string(query)]
    |> put_status_filter(active_filters)
    |> put_project_filter(active_filters)
  end

  defp put_status_filter(opts, active_filters) do
    case Enum.find(active_filters, &(&1.id == "status")) do
      %{operator: :==, value: value} when is_binary(value) and value != "" ->
        Keyword.put(opts, :status, String.to_existing_atom(value))

      _ ->
        opts
    end
  end

  defp put_project_filter(opts, active_filters) do
    case Enum.find(active_filters, &(&1.id == "project")) do
      %{operator: :==, value: value} when is_binary(value) and value != "" ->
        Keyword.put(opts, :project_id, value)

      _ ->
        opts
    end
  end

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
    status_options = Issue.statuses() |> Enum.map(&Atom.to_string/1)
    projects = Projects.list_projects()

    [
      %Filter.Filter{
        id: "status",
        display_name: dgettext("dashboard_errors", "Status"),
        type: :option,
        options: status_options,
        options_display_names: Map.new(status_options, &{&1, status_label(String.to_atom(&1))}),
        operator: :==,
        searchable: false,
        value: nil
      },
      %Filter.Filter{
        id: "project",
        display_name: dgettext("dashboard_errors", "Project"),
        type: :option,
        options: Enum.map(projects, & &1.id),
        options_display_names: Map.new(projects, &{&1.id, &1.name}),
        operator: :==,
        searchable: true,
        value: nil
      }
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp project_name(%Issue{project: %{name: name}}), do: name
  defp project_name(_), do: "-"

  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M:%S UTC")
  defp format_datetime(_datetime), do: "-"

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_date(_datetime), do: "-"

  defp status_label(:unresolved), do: dgettext("dashboard_errors", "Unresolved")
  defp status_label(:resolved), do: dgettext("dashboard_errors", "Resolved")
  defp status_label(:ignored), do: dgettext("dashboard_errors", "Ignored")
  defp status_label(_), do: "-"

  defp status_color(:unresolved), do: "warning"
  defp status_color(:resolved), do: "success"
  defp status_color(:ignored), do: "neutral"
  defp status_color(_), do: "neutral"

  defp level_label(:fatal), do: dgettext("dashboard_errors", "Fatal")
  defp level_label(:error), do: dgettext("dashboard_errors", "Error")
  defp level_label(:warning), do: dgettext("dashboard_errors", "Warning")
  defp level_label(:info), do: dgettext("dashboard_errors", "Info")
  defp level_label(:debug), do: dgettext("dashboard_errors", "Debug")
  defp level_label(_), do: "-"

  defp level_color(:fatal), do: "destructive"
  defp level_color(:error), do: "destructive"
  defp level_color(:warning), do: "warning"
  defp level_color(:info), do: "information"
  defp level_color(:debug), do: "neutral"
  defp level_color(_), do: "neutral"
end

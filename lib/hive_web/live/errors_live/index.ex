defmodule HiveWeb.ErrorsLive.Index do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  import Noora.DatePicker
  import Noora.Filter

  alias Phoenix.LiveView.JS
  alias Hive.Errors
  alias Hive.Errors.Issue
  alias Hive.Errors.Policy
  alias Hive.Projects
  alias HiveWeb.Helpers.DatePicker
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
       |> assign(:trend_series, %{})
       |> assign(:window_counts, %{})
       |> assign(OpenGraph.assigns(open_graph()))}
    else
      {:ok, redirect_to_home(socket)}
    end
  end

  def handle_params(params, uri, socket) do
    %{preset: preset, period: {from, to}} = DatePicker.date_picker_params(params, "errors")

    query_params = Query.query_params(uri)
    page = Query.parse_page(params["page"])
    query = params["q"] || ""

    environments = Errors.distinct_environments(from: from, to: to)
    available_filters = define_filters(environments)
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    list_opts = list_opts(query, active_filters, page, from, to)
    {issues, meta} = Errors.paginate_issues(list_opts)

    issue_ids = Enum.map(issues, & &1.id)
    trend_series = Errors.event_trends(issue_ids, from, to)
    window_counts = Errors.event_counts_in_window(issue_ids, from, to)

    socket =
      socket
      |> assign(:uri, uri_from_query_params(query_params))
      |> assign(:issues, issues)
      |> assign(:issues_meta, meta)
      |> assign(:available_filters, available_filters)
      |> assign(:active_filters, active_filters)
      |> assign(:query, query)
      |> assign(:search_form, to_form(%{"query" => query}, as: :search))
      |> assign(:errors_preset, preset)
      |> assign(:errors_period, {from, to})
      |> assign(:trend_series, trend_series)
      |> assign(:window_counts, window_counts)

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    trimmed = Query.present_string(query)

    updated =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(fn params ->
        if trimmed, do: Map.put(params, "q", trimmed), else: Map.delete(params, "q")
      end)

    {:noreply, push_patch(socket, to: ~p"/errors?#{updated}", replace: true)}
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

  def handle_event("resolve_issue", %{"id" => id}, socket),
    do: transition_status(socket, id, :resolved)

  def handle_event("unresolve_issue", %{"id" => id}, socket),
    do: transition_status(socket, id, :unresolved)

  def handle_event(
        "errors_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    updated =
      if preset == "custom" do
        socket
        |> current_query_params()
        |> Map.delete("page")
        |> Map.put("errors-date-range", "custom")
        |> Map.put("errors-start-date", start_date)
        |> Map.put("errors-end-date", end_date)
      else
        socket
        |> current_query_params()
        |> Map.delete("page")
        |> Map.put("errors-date-range", preset)
        |> Map.delete("errors-start-date")
        |> Map.delete("errors-end-date")
      end

    {:noreply, push_patch(socket, to: ~p"/errors?#{updated}")}
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
              <div data-part="left-controls">
                <.filter_dropdown
                  id="errors-filter"
                  label={dgettext("dashboard_errors", "Filter")}
                  available_filters={@available_filters}
                  active_filters={@active_filters}
                  on_select="add_filter"
                />

                <.date_picker
                  id="errors-date-range-picker"
                  name="errors-date-range"
                  presets={date_presets()}
                  selected_preset={@errors_preset}
                  period={@errors_period}
                  on_period_change="errors_period_changed"
                  max={Date.utc_today()}
                >
                  <:actions>
                    <.button
                      label={dgettext("dashboard_errors", "Cancel")}
                      variant="secondary"
                      phx-click={
                        JS.dispatch("phx:date-picker-cancel",
                          detail: %{id: "errors-date-range-picker"}
                        )
                      }
                    />
                    <.button
                      label={dgettext("dashboard_errors", "Apply")}
                      phx-click={
                        JS.dispatch("phx:date-picker-apply",
                          detail: %{id: "errors-date-range-picker"}
                        )
                      }
                    />
                  </:actions>
                </.date_picker>
              </div>

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
                  <div data-part="issue-cell">
                    <span data-part="issue-title">{issue.title}</span>
                    <span data-part="issue-meta">
                      <.badge
                        label={level_label(issue.level)}
                        color={level_color(issue.level)}
                        style="light-fill"
                        size="small"
                      />
                      <.badge
                        label={status_label(issue.status)}
                        color={status_color(issue.status)}
                        style="light-fill"
                        size="small"
                      />
                      <span data-part="culprit">
                        {issue.culprit || dgettext("dashboard_errors", "No location")}
                      </span>
                      <span data-part="project">· {project_name(issue)}</span>
                    </span>
                  </div>
                </.link>
              </:col>
              <:col :let={issue} label={dgettext("dashboard_errors", "Last seen")}>
                <span data-part="relative" title={format_datetime(issue.last_seen)}>
                  {relative_time(issue.last_seen)}
                </span>
              </:col>
              <:col :let={issue} label={dgettext("dashboard_errors", "Age")}>
                <span data-part="relative" title={format_datetime(issue.first_seen)}>
                  {relative_time(issue.first_seen)}
                </span>
              </:col>
              <:col :let={issue} label={dgettext("dashboard_errors", "Trend")}>
                <div
                  data-part="trend"
                  title={
                    dgettext("dashboard_errors", "%{count} events in the selected window",
                      count: format_integer(events_in_window(issue, @window_counts))
                    )
                  }
                >
                  <.chart
                    id={"trend-#{issue.id}"}
                    type="bar"
                    series={Map.get(@trend_series, issue.id, [])}
                    show_legend={false}
                    extra_options={sparkline_options()}
                    style="width: 140px; height: 40px;"
                  />
                </div>
              </:col>
              <:col :let={issue} label={dgettext("dashboard_errors", "Events")}>
                <span data-part="events" title={
                  dgettext("dashboard_errors", "%{total} total across all time",
                    total: format_integer(issue.event_count)
                  )
                }>
                  {format_integer(events_in_window(issue, @window_counts))}
                </span>
              </:col>
              <:col :let={issue} label="">
                <div data-part="row-actions">
                  <.button
                    :if={issue.status == :unresolved}
                    variant="secondary"
                    size="small"
                    label={dgettext("dashboard_errors", "Resolve")}
                    title={dgettext("dashboard_errors", "Mark as resolved")}
                    phx-click="resolve_issue"
                    phx-value-id={issue.id}
                  >
                    <:icon_left><.check /></:icon_left>
                  </.button>
                  <.button
                    :if={issue.status == :resolved}
                    variant="secondary"
                    size="small"
                    label={dgettext("dashboard_errors", "Reopen")}
                    title={dgettext("dashboard_errors", "Mark as unresolved")}
                    phx-click="unresolve_issue"
                    phx-value-id={issue.id}
                  >
                    <:icon_left><.history /></:icon_left>
                  </.button>
                </div>
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

  defp sparkline_options do
    %{
      grid: %{left: 0, right: 0, top: 4, bottom: 4, containLabel: false},
      xAxis: %{show: false, type: "category"},
      yAxis: %{show: false},
      tooltip: %{show: false},
      legend: %{show: false}
    }
  end

  defp transition_status(socket, id, status) do
    action =
      case status do
        :resolved -> :error_issue_resolve
        :unresolved -> :error_issue_resolve
        :ignored -> :error_issue_ignore
      end

    cond do
      not Policy.authorize?(action, socket.assigns[:current_user], nil) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_errors", "You do not have permission to change this issue.")
         )}

      true ->
        with {:ok, issue} <- Errors.fetch_issue(id),
             {:ok, _updated} <- Errors.update_issue_status(issue, status) do
          {:noreply, push_patch(socket, to: patch_url(socket), replace: true)}
        else
          _ ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("dashboard_errors", "Could not update the issue.")
             )}
        end
    end
  end

  defp patch_url(socket) do
    params = current_query_params(socket)

    case URI.encode_query(params) do
      "" -> ~p"/errors"
      qs -> ~p"/errors?#{qs}"
    end
  end

  defp date_presets do
    [
      %{
        id: "last-1-hour",
        label: dgettext("dashboard_errors", "Last 1 hour"),
        period: {1, :hour}
      },
      %{
        id: "last-24-hours",
        label: dgettext("dashboard_errors", "Last 24 hours"),
        period: {24, :hour}
      },
      %{id: "last-7-days", label: dgettext("dashboard_errors", "Last 7 days"), period: {7, :day}},
      %{
        id: "last-30-days",
        label: dgettext("dashboard_errors", "Last 30 days"),
        period: {30, :day}
      },
      %{
        id: "last-12-months",
        label: dgettext("dashboard_errors", "Last 12 months"),
        period: {12, :month}
      },
      %{id: "custom", label: dgettext("dashboard_errors", "Custom")}
    ]
  end

  defp events_in_window(issue, window_counts), do: Map.get(window_counts, issue.id, 0)

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
    |> put_flash(:error, dgettext("dashboard_errors", "You do not have access to errors."))
    |> push_navigate(to: ~p"/")
  end

  defp page_link(uri, page) do
    "?" <> Query.put(uri.query, "page", Integer.to_string(page))
  end

  defp list_opts(query, active_filters, page, from, to) do
    [page: page, page_size: @page_size, search: Query.present_string(query), from: from, to: to]
    |> put_status_filter(active_filters)
    |> put_project_filter(active_filters)
    |> put_env_filter(active_filters)
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

  defp put_env_filter(opts, active_filters) do
    case Enum.find(active_filters, &(&1.id == "environment")) do
      %{operator: :==, value: value} when is_binary(value) and value != "" ->
        Keyword.put(opts, :environment, value)

      _ ->
        opts
    end
  end

  defp current_query_params(%{assigns: %{uri: uri}}) do
    uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp current_query_params(_), do: %{}

  defp uri_from_query_params(params) do
    case URI.encode_query(params) do
      "" -> URI.parse("")
      query -> URI.parse("?" <> query)
    end
  end

  defp define_filters(environments) do
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
      },
      %Filter.Filter{
        id: "environment",
        display_name: dgettext("dashboard_errors", "Environment"),
        type: :option,
        options: environments,
        options_display_names: Map.new(environments, &{&1, &1}),
        operator: :==,
        searchable: true,
        value: nil
      }
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp project_name(%Issue{project: %{name: name}}), do: name
  defp project_name(_), do: "-"

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp format_datetime(_), do: "-"

  defp format_integer(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_integer(_), do: "0"

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 5 -> dgettext("dashboard_errors", "just now")
      diff < 60 -> dgettext("dashboard_errors", "%{n}s ago", n: diff)
      diff < 3600 -> dgettext("dashboard_errors", "%{n}m ago", n: div(diff, 60))
      diff < 86_400 -> dgettext("dashboard_errors", "%{n}h ago", n: div(diff, 3600))
      diff < 30 * 86_400 -> dgettext("dashboard_errors", "%{n}d ago", n: div(diff, 86_400))
      diff < 365 * 86_400 -> dgettext("dashboard_errors", "%{n}mo ago", n: div(diff, 30 * 86_400))
      true -> dgettext("dashboard_errors", "%{n}y ago", n: div(diff, 365 * 86_400))
    end
  end

  defp relative_time(_), do: "-"

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

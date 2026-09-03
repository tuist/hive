defmodule HiveWeb.FlightLive.Index do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  import Noora.Filter

  alias Hive.Flights
  alias Hive.Flights.Policy
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.Utilities.Query
  alias Noora.Filter

  @page_size 10

  def open_graph do
    %{
      description:
        dgettext(
          "dashboard_flights",
          "Inspect durable agent executions, their product signals, and their continuation context."
        ),
      section_label: dgettext("dashboard_flights", "Flights"),
      highlights: [
        dgettext("dashboard_flights", "Sandbox history"),
        dgettext("dashboard_flights", "Forage context"),
        dgettext("dashboard_flights", "Local continuation")
      ],
      id: "flights",
      path: "/flights",
      title: dgettext("dashboard_flights", "Flights")
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    if Policy.authorize?(:flight_read, socket.assigns[:current_user], nil) do
      {:ok,
       socket
       |> assign(
         :page_title,
         dgettext("dashboard_flights", "Flights · %{product}",
           product: socket.assigns.product_name
         )
       )
       |> assign(:available_filters, [])
       |> assign(:active_filters, [])
       |> assign(:flights, [])
       |> assign(:meta, empty_meta())
       |> assign(:query, "")
       |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
       |> assign(:uri, URI.parse("/flights"))
       |> assign(:atom_feed, %{
         title: dgettext("dashboard_flights", "Hive · Flights"),
         atom_href: "/flights/atom.xml",
         rss_href: "/flights/rss.xml"
       })
       |> assign(OpenGraph.assigns(open_graph()))}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         dgettext("dashboard_flights", "You do not have access to Flights.")
       )
       |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    user = socket.assigns.current_user
    available_filters = define_filters(user)
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)
    query = params["q"] || ""
    page = Query.parse_page(params["page"])

    {flights, meta} =
      Flights.list_flights_for_user(user, list_opts(query, active_filters, page))

    {:noreply,
     socket
     |> assign(:uri, uri |> Query.query_params() |> uri_from_query_params())
     |> assign(:available_filters, available_filters)
     |> assign(:active_filters, active_filters)
     |> assign(:flights, flights)
     |> assign(:meta, meta)
     |> assign(:query, query)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/flights?#{flight_query_params(query, socket.assigns.active_filters)}",
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
     |> push_patch(to: ~p"/flights?#{updated_params}")
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
     |> push_patch(to: ~p"/flights?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
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
      member?={@member?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
      specs_have_new_activity?={@specs_have_new_activity?}
    >
      <section id="flights">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{dgettext("dashboard_flights", "Flights")}</h1>
            <p>
              {dgettext(
                "dashboard_flights",
                "Durable agent executions with the product signal, sandbox outcome, and context needed to continue locally."
              )}
            </p>
          </div>
          <div data-part="header-actions">
            <Layouts.feeds_dropdown
              id="flights-feeds"
              atom_href={@atom_feed.atom_href}
              rss_href={@atom_feed.rss_href}
            />
          </div>
        </div>

        <.card title={dgettext("dashboard_flights", "Execution history")} icon="player_play">
          <.card_section>
            <div data-part="table-toolbar">
              <.filter_dropdown
                id="flights-filter"
                label={dgettext("dashboard_flights", "Filter")}
                available_filters={@available_filters}
                active_filters={@active_filters}
                on_select="add_filter"
              />

              <div data-part="search">
                <.form
                  id="flights-search-form"
                  for={@search_form}
                  phx-change="search"
                  phx-submit="search"
                >
                  <.text_input
                    id="flights-search"
                    field={@search_form[:query]}
                    type="search"
                    show_suffix={false}
                    placeholder={dgettext("dashboard_flights", "Search signal, repository, or result...")}
                  />
                </.form>
              </div>
            </div>

            <div :if={@active_filters != []} data-part="active-filters">
              <.active_filter :for={filter <- @active_filters} filter={filter} />
            </div>

            <div data-part="table-scroll">
              <.table id="flights-table" rows={@flights}>
                <:col :let={flight} label={dgettext("dashboard_flights", "Started") }>
                  <.text_cell
                    label={format_date(flight.inserted_at)}
                    sublabel={format_time(flight.inserted_at)}
                  />
                </:col>
                <:col :let={flight} label={dgettext("dashboard_flights", "Flight") }>
                  <.link navigate={Flights.path(flight)} data-part="flight-link">
                    <.text_and_description_cell
                      label={Flights.title(flight)}
                      description={Flights.summary(flight)}
                    />
                  </.link>
                </:col>
                <:col :let={flight} label={dgettext("dashboard_flights", "Forage item") }>
                  <.link
                    :if={Flights.forage_item_path(flight.forage_item)}
                    navigate={Flights.forage_item_path(flight.forage_item)}
                    data-part="forage-link"
                  >
                    <.text_cell label={flight.forage_item.title} />
                  </.link>
                  <.text_cell
                    :if={!Flights.forage_item_path(flight.forage_item)}
                    label={dgettext("dashboard_flights", "Unavailable")}
                  />
                </:col>
                <:col :let={flight} label={dgettext("dashboard_flights", "Repository") }>
                  <.text_cell label={flight.repository_full_name} />
                </:col>
                <:col :let={flight} label={dgettext("dashboard_flights", "Objective") }>
                  <.badge_cell
                    label={Flights.objective_label(flight.objective)}
                    color="neutral"
                    style="light-fill"
                  />
                </:col>
                <:col :let={flight} label={dgettext("dashboard_flights", "Duration") }>
                  <.text_cell label={duration(flight)} />
                </:col>
                <:col :let={flight} label={dgettext("dashboard_flights", "Status") }>
                  <.badge_cell
                    label={Flights.status_label(flight.status)}
                    color={Flights.status_color(flight.status)}
                    style="light-fill"
                  />
                </:col>
                <:empty_state>
                  <.table_empty_state
                    icon="player_play"
                    title={dgettext("dashboard_flights", "No Flights found")}
                    subtitle={
                      dgettext(
                        "dashboard_flights",
                        "Start a Flight from a supported Forage item or adjust the current filters."
                      )
                    }
                  />
                </:empty_state>
              </.table>
            </div>

            <div :if={@meta.total_pages > 1} data-part="pagination">
              <.button
                variant="secondary"
                label={dgettext("dashboard_flights", "Prev")}
                disabled={@meta.current_page <= 1}
                patch={page_link(@uri, max(1, @meta.current_page - 1))}
              >
                <:icon_left><.chevron_left /></:icon_left>
              </.button>
              <.button
                variant="secondary"
                label={dgettext("dashboard_flights", "Next")}
                disabled={@meta.current_page >= @meta.total_pages}
                patch={page_link(@uri, min(@meta.total_pages, @meta.current_page + 1))}
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

  defp define_filters(user) do
    options = Flights.filter_options(user)

    [
      option_filter(
        "status",
        dgettext("dashboard_flights", "Status"),
        Enum.map(options.statuses, &Atom.to_string/1),
        Map.new(options.statuses, &{Atom.to_string(&1), Flights.status_label(&1)}),
        false
      ),
      option_filter(
        "objective",
        dgettext("dashboard_flights", "Objective"),
        Enum.map(options.objectives, &Atom.to_string/1),
        Map.new(options.objectives, &{Atom.to_string(&1), Flights.objective_label(&1)}),
        false
      ),
      option_filter(
        "outcome",
        dgettext("dashboard_flights", "Outcome"),
        Enum.map(options.objective_outcomes, &Atom.to_string/1),
        Map.new(
          options.objective_outcomes,
          &{Atom.to_string(&1), Flights.objective_outcome_label(&1)}
        ),
        false
      ),
      option_filter(
        "runner",
        dgettext("dashboard_flights", "Runner"),
        options.runners,
        Map.new(options.runners, &{&1, runner_label(&1)}),
        true
      ),
      option_filter(
        "repository",
        dgettext("dashboard_flights", "Repository"),
        options.repositories,
        Map.new(options.repositories, &{&1, &1}),
        true
      )
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp option_filter(id, display_name, options, display_names, searchable?) do
    %Filter.Filter{
      id: id,
      display_name: display_name,
      type: :option,
      options: options,
      options_display_names: display_names,
      operator: :==,
      searchable: searchable?,
      value: nil
    }
  end

  defp list_opts(query, active_filters, page) do
    [page: page, page_size: @page_size, query: Query.present_string(query)]
    |> put_filter(active_filters, "status", :status)
    |> put_filter(active_filters, "objective", :objective)
    |> put_filter(active_filters, "outcome", :objective_outcome)
    |> put_filter(active_filters, "runner", :runner)
    |> put_filter(active_filters, "repository", :repository)
  end

  defp put_filter(opts, active_filters, filter_id, key) do
    case Enum.find(active_filters, &(&1.id == filter_id)) do
      %{operator: :==, value: value} -> Keyword.put(opts, key, value)
      _filter -> opts
    end
  end

  defp flight_query_params(query, active_filters) do
    active_filters
    |> Filter.Operations.encode_filters_to_query()
    |> Query.put_present("q", Query.present_string(query))
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

  defp page_link(uri, page), do: "?" <> Query.put(uri.query, "page", page)

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_date(_datetime), do: "-"
  defp format_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M UTC")
  defp format_time(_datetime), do: "-"

  defp duration(%{started_at: %DateTime{} = started_at} = flight) do
    finished_at = flight.completed_at || DateTime.utc_now()
    seconds = max(0, DateTime.diff(finished_at, started_at, :second))

    cond do
      seconds < 60 -> dgettext("dashboard_flights", "Under a minute")
      seconds < 3_600 -> dgettext("dashboard_flights", "%{count} min", count: div(seconds, 60))
      true -> dgettext("dashboard_flights", "%{count} hr", count: div(seconds, 3_600))
    end
  end

  defp duration(_flight), do: "-"

  defp runner_label(runner) do
    runner
    |> String.replace(["_", "-"], " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp empty_meta do
    %{
      current_page: 1,
      page_size: @page_size,
      total_count: 0,
      total_pages: 1,
      has_next_page?: false,
      has_previous_page?: false
    }
  end
end

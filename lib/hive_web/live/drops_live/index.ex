defmodule HiveWeb.DropsLive.Index do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  import Noora.Filter

  alias Hive.Drops
  alias Hive.Domains
  alias Hive.Projects
  alias HiveWeb.Layouts
  alias HiveWeb.Markdown
  alias HiveWeb.OpenGraph
  alias HiveWeb.Utilities.Query
  alias Noora.Filter

  @page_size 10

  def open_graph(drops \\ [], meta \\ nil) do
    total_entries = total_entries(drops, meta)

    %{
      description:
        dgettext(
          "dashboard_drops",
          "Shipped updates from connected project releases and changelog feeds."
        ),
      section_label: dgettext("dashboard_drops", "Drops"),
      highlights: drops_highlights(drops, total_entries),
      id: "drops",
      path: "/drops",
      title: dgettext("dashboard_drops", "Drops")
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       :page_title,
       dgettext("dashboard_drops", "Drops · %{product}", product: socket.assigns.product_name)
     )
     |> assign(:available_filters, [])
     |> assign(:active_filters, [])
     |> assign(:drops, [])
     |> assign(:drops_meta, %{
       current_page: 1,
       page_size: @page_size,
       total_entries: 0,
       total_pages: 1
     })
     |> assign(:domains, [])
     |> assign(:projects, [])
     |> assign(:query, "")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign(:uri, URI.parse("/drops"))
     |> assign(:atom_feed, %{
       title: dgettext("dashboard_drops", "Hive · Drops"),
       atom_href: "/drops/atom.xml",
       rss_href: "/drops/rss.xml"
     })
     |> assign(OpenGraph.assigns(open_graph()))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    user = socket.assigns[:current_user]
    domains = Domains.list_visible_domains(user)
    projects = Projects.list_visible_projects(user)
    available_filters = define_filters(domains, projects)
    query_params = Query.query_params(uri)

    page = Query.parse_page(params["page"])
    query = params["q"] || ""
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    {drops, meta} =
      Drops.list_drops(list_opts(user, query, active_filters, page))

    socket =
      socket
      |> assign(:uri, uri_from_query_params(query_params))
      |> assign(:domains, domains)
      |> assign(:projects, projects)
      |> assign(:drops, drops)
      |> assign(:drops_meta, meta)
      |> assign(:available_filters, available_filters)
      |> assign(:active_filters, active_filters)
      |> assign(:query, query)
      |> assign(:atom_feed, atom_feed(params))
      |> assign(:search_form, to_form(%{"query" => query}, as: :search))
      |> assign(OpenGraph.assigns(open_graph(drops, meta)))

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/drops?#{drops_query_params(query, socket.assigns.active_filters)}",
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
     |> push_patch(to: ~p"/drops?#{updated_params}")
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
     |> push_patch(to: ~p"/drops?#{updated_params}")
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
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
    >
      <section id="drops">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{dgettext("dashboard_drops", "Drops")}</h1>
            <p>
              {dgettext(
                "dashboard_drops",
                "Shipped updates from GitHub releases and changelog feeds across every domain."
              )}
            </p>
          </div>
          <div data-part="header-actions">
            <.link navigate={~p"/drops/subscribe"}>
              <.button label={dgettext("dashboard_drops", "Subscribe")} size="medium" variant="secondary">
                <:icon_left><.icon name="rss" /></:icon_left>
              </.button>
            </.link>
          </div>
        </div>

        <.card title={dgettext("dashboard_drops", "Activity")} icon="package">
          <.card_section>
            <div data-part="table-toolbar">
              <.filter_dropdown
                id="drops-filter"
                label={dgettext("dashboard_drops", "Filter")}
                available_filters={@available_filters}
                active_filters={@active_filters}
                on_select="add_filter"
              />

              <div data-part="search">
                <.form
                  id="drops-search-form"
                  for={@search_form}
                  phx-change="search"
                  phx-submit="search"
                >
                  <.text_input
                    id="drops-search"
                    field={@search_form[:query]}
                    type="search"
                    show_suffix={false}
                    placeholder={dgettext("dashboard_drops", "Search title or body...")}
                  />
                </.form>
              </div>
            </div>

            <div :if={@active_filters != []} data-part="active-filters">
              <.active_filter :for={filter <- @active_filters} filter={filter} />
            </div>

            <div data-part="table-scroll">
              <.table id="drops-table" rows={@drops}>
                <:col :let={drop} label={dgettext("dashboard_drops", "Published")}>
                  <time data-part="published-cell" datetime={published_iso8601(drop.published_at)}>
                    <span data-part="published-date">{format_date(drop.published_at)}</span>
                    <span data-part="published-time">{format_time(drop.published_at)}</span>
                  </time>
                </:col>
                <:col :let={drop} label={dgettext("dashboard_drops", "Title")}>
                  <.link navigate={~p"/drops/#{drop.number}"} data-part="title-link">
                    <.text_and_description_cell
                      label={Markdown.inline(drop.title)}
                      description={truncate(drop.body)}
                    />
                  </.link>
                </:col>
                <:col :let={drop} label={dgettext("dashboard_drops", "Project")}>
                  <.text_cell label={project_chips(drop)} />
                </:col>
                <:col :let={drop} label={dgettext("dashboard_drops", "Domains")}>
                  <.text_cell label={domain_chips(drop.domains)} />
                </:col>
                <:col :let={drop} label={dgettext("dashboard_drops", "Version")}>
                  <.text_cell :if={drop.version} label={drop.version} />
                  <.text_cell :if={is_nil(drop.version)} label="—" />
                </:col>
                <:col :let={drop} label={dgettext("dashboard_drops", "Source")}>
                  <.badge_cell
                    label={Drops.source_type_label(drop.source_type)}
                    color={source_badge_color(drop.source_type)}
                    style="light-fill"
                  />
                </:col>
                <:empty_state>
                  <.table_empty_state
                    icon="package"
                    title={dgettext("dashboard_drops", "No drops yet")}
                    subtitle={
                      dgettext(
                        "dashboard_drops",
                        "Once a release is published or a changelog updates, drops will surface here."
                      )
                    }
                  />
                </:empty_state>
              </.table>
            </div>

            <div :if={@drops_meta.total_pages > 1} data-part="pagination">
              <.button
                variant="secondary"
                label={dgettext("dashboard_drops", "Prev")}
                disabled={@drops_meta.current_page <= 1}
                patch={page_link(@uri, max(1, @drops_meta.current_page - 1))}
              >
                <:icon_left><.chevron_left /></:icon_left>
              </.button>
              <.button
                variant="secondary"
                label={dgettext("dashboard_drops", "Next")}
                disabled={@drops_meta.current_page >= @drops_meta.total_pages}
                patch={
                  page_link(
                    @uri,
                    min(@drops_meta.total_pages, @drops_meta.current_page + 1)
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

  defp atom_feed(params) do
    domain_ids = Query.csv_list(params["domain_ids"])
    project_ids = Query.csv_list(params["project_ids"])
    query = drops_filter_query(project_ids, domain_ids)

    %{
      title: dgettext("dashboard_drops", "Hive · Drops"),
      atom_href: "/drops/atom.xml" <> query,
      rss_href: "/drops/rss.xml" <> query
    }
  end

  defp page_link(uri, page) do
    "?" <> Query.put(uri.query, "page", Integer.to_string(page))
  end

  defp drops_query_params(query, active_filters) do
    active_filters
    |> Filter.Operations.encode_filters_to_query()
    |> Query.put_present("q", Query.present_string(query))
  end

  defp list_opts(user, query, active_filters, page) do
    [user: user, page: page, page_size: @page_size, query: Query.present_string(query)]
    |> put_domain_filter(active_filters)
    |> put_project_filter(active_filters)
    |> put_source_type_filter(active_filters)
  end

  defp put_domain_filter(opts, active_filters) do
    case Enum.find(active_filters, &(&1.id == "domain")) do
      %{operator: :==, value: value} when is_binary(value) and value != "" ->
        Keyword.put(opts, :domain_ids, [value])

      _other ->
        opts
    end
  end

  defp put_project_filter(opts, active_filters) do
    case Enum.find(active_filters, &(&1.id == "project")) do
      %{operator: :==, value: value} when is_binary(value) and value != "" ->
        Keyword.put(opts, :project_ids, [value])

      _other ->
        opts
    end
  end

  defp put_source_type_filter(opts, active_filters) do
    case Enum.find(active_filters, &(&1.id == "source_type")) do
      %{operator: :==, value: value} when is_binary(value) and value != "" ->
        Keyword.put(opts, :source_type, parse_source_type(value))

      _other ->
        opts
    end
  end

  defp parse_source_type("github_release"), do: :github_release
  defp parse_source_type("rss"), do: :rss
  defp parse_source_type(_other), do: nil

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

  defp define_filters(domains, projects) do
    domain_options =
      domains
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    domain_display_names =
      Map.new(domains, fn domain -> {domain.id, domain.name} end)

    project_options =
      projects
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    project_display_names =
      Map.new(projects, fn project -> {project.id, project.name} end)

    [
      %Filter.Filter{
        id: "project",
        display_name: dgettext("dashboard_drops", "Project"),
        type: :option,
        options: project_options,
        options_display_names: project_display_names,
        operator: :==,
        searchable: true,
        value: nil
      },
      %Filter.Filter{
        id: "domain",
        display_name: dgettext("dashboard_drops", "Domain"),
        type: :option,
        options: domain_options,
        options_display_names: domain_display_names,
        operator: :==,
        searchable: true,
        value: nil
      },
      %Filter.Filter{
        id: "source_type",
        display_name: dgettext("dashboard_drops", "Source"),
        type: :option,
        options: ["github_release", "rss"],
        options_display_names: %{
          "github_release" => dgettext("dashboard_drops", "GitHub"),
          "rss" => dgettext("dashboard_drops", "RSS")
        },
        operator: :==,
        searchable: false,
        value: nil
      }
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp source_badge_color(:github_release), do: "focus"
  defp source_badge_color(:rss), do: "information"
  defp source_badge_color(_other), do: "neutral"

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_date(_other), do: "-"

  defp format_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M UTC")
  defp format_time(_other), do: "-"

  defp published_iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp published_iso8601(_other), do: nil

  defp truncate(nil), do: nil
  defp truncate(body) when is_binary(body), do: Markdown.preview(body, 140)

  defp domain_chips([]), do: dgettext("dashboard_drops", "Unclassified")
  defp domain_chips(nil), do: dgettext("dashboard_drops", "Unclassified")
  defp domain_chips(domains), do: Enum.map_join(domains, ", ", & &1.name)

  defp project_chips(drop) do
    drop
    |> Drops.projects_for_drop()
    |> Enum.map(& &1.name)
    |> case do
      [] -> "—"
      names -> Enum.join(names, ", ")
    end
  end

  defp drops_filter_query([], []), do: ""

  defp drops_filter_query(project_ids, domain_ids) do
    params =
      %{}
      |> maybe_put_csv("project_ids", project_ids)
      |> maybe_put_csv("domain_ids", domain_ids)

    "?" <> URI.encode_query(params)
  end

  defp maybe_put_csv(params, _key, []), do: params
  defp maybe_put_csv(params, key, values), do: Map.put(params, key, Enum.join(values, ","))

  defp total_entries(_drops, %{total_entries: total}) when is_integer(total), do: total
  defp total_entries(drops, _meta), do: length(drops)

  defp drops_highlights(drops, total_entries) do
    [
      count_label(total_entries)
      | source_highlights(drops)
    ]
    |> Kernel.++([dgettext("dashboard_drops", "Subscribe per domain")])
    |> Enum.uniq()
    |> Enum.take(3)
  end

  defp source_highlights(drops) do
    drops
    |> Enum.map(& &1.source_type)
    |> Enum.uniq()
    |> Enum.flat_map(fn
      :github_release -> [dgettext("dashboard_drops", "GitHub releases")]
      :rss -> [dgettext("dashboard_drops", "Changelog feeds")]
      _other -> []
    end)
    |> case do
      [] ->
        [
          dgettext("dashboard_drops", "Connected releases"),
          dgettext("dashboard_drops", "Changelog feeds")
        ]

      highlights ->
        highlights
    end
  end

  defp count_label(1), do: dgettext("dashboard_drops", "1 drop")

  defp count_label(count) when is_integer(count),
    do: dgettext("dashboard_drops", "%{count} drops", count: count)

  defp count_label(_count), do: dgettext("dashboard_drops", "0 drops")
end

defmodule HiveWeb.DropsLive.Index do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  import Noora.Filter

  alias Hive.Drops
  alias Hive.Domains
  alias HiveWeb.Layouts
  alias HiveWeb.Markdown
  alias HiveWeb.OpenGraph
  alias HiveWeb.Utilities.Query
  alias Noora.Filter

  @page_size 10

  def open_graph do
    %{
      description:
        "Shipped updates from GitHub releases and changelog feeds across every domain.",
      eyebrow: "Drops",
      highlights: ["GitHub releases", "RSS / Atom changelogs", "Subscribe per domain"],
      id: "drops",
      path: "/drops",
      title: "Drops"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Drops · #{socket.assigns.product_name}")
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
     |> assign(:query, "")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign(:uri, URI.parse("/drops"))
     |> assign(:atom_feed, %{
       title: "Hive · Drops",
       atom_href: "/drops/atom.xml",
       rss_href: "/drops/rss.xml"
     })
     |> assign(OpenGraph.assigns(open_graph()))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    user = socket.assigns[:current_user]
    domains = Domains.list_visible_domains(user)
    available_filters = define_filters(domains)
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
      |> assign(:drops, drops)
      |> assign(:drops_meta, meta)
      |> assign(:available_filters, available_filters)
      |> assign(:active_filters, active_filters)
      |> assign(:query, query)
      |> assign(:atom_feed, atom_feed(params))
      |> assign(:search_form, to_form(%{"query" => query}, as: :search))

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
            <.badge label="Drops" color="information" style="light-fill" />
            <h1>Drops</h1>
            <p>Shipped updates from GitHub releases and changelog feeds across every domain.</p>
          </div>
          <div data-part="header-actions">
            <.link navigate={~p"/drops/subscribe"}>
              <.button label="Subscribe" size="medium" variant="secondary">
                <:icon_left><.icon name="rss" /></:icon_left>
              </.button>
            </.link>
          </div>
        </div>

        <.card title="Activity" icon="package">
          <.card_section>
            <div data-part="table-toolbar">
              <.filter_dropdown
                id="drops-filter"
                label="Filter"
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
                    placeholder="Search title or body..."
                  />
                </.form>
              </div>
            </div>

            <div :if={@active_filters != []} data-part="active-filters">
              <.active_filter :for={filter <- @active_filters} filter={filter} />
            </div>

            <.table id="drops-table" rows={@drops}>
              <:col :let={drop} label="Published">
                <.text_cell
                  label={format_datetime(drop.published_at)}
                  sublabel={format_date(drop.published_at)}
                />
              </:col>
              <:col :let={drop} label="Title">
                <.link navigate={~p"/drops/#{drop.id}"} data-part="title-link">
                  <.text_and_description_cell
                    label={Markdown.inline(drop.title)}
                    description={truncate(drop.body)}
                  />
                </.link>
              </:col>
              <:col :let={drop} label="Version">
                <.text_cell :if={drop.version} label={drop.version} />
                <.text_cell :if={is_nil(drop.version)} label="—" />
              </:col>
              <:col :let={drop} label="Project">
                <.text_cell label={project_chips(drop.domains)} />
              </:col>
              <:col :let={drop} label="Domains">
                <.text_cell label={domain_chips(drop.domains)} />
              </:col>
              <:col :let={drop} label="Source">
                <.badge_cell
                  label={Drops.source_type_label(drop.source_type)}
                  color={source_badge_color(drop.source_type)}
                  style="light-fill"
                />
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="package"
                  title="No drops yet"
                  subtitle="Once a release is published or a changelog updates, drops will surface here."
                />
              </:empty_state>
            </.table>

            <div :if={@drops_meta.total_pages > 1} data-part="pagination">
              <.button
                variant="secondary"
                label="Prev"
                disabled={@drops_meta.current_page <= 1}
                patch={page_link(@uri, max(1, @drops_meta.current_page - 1))}
              >
                <:icon_left><.chevron_left /></:icon_left>
              </.button>
              <.button
                variant="secondary"
                label="Next"
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
    domain_ids = parse_domain_ids(params["domain_ids"])
    query = if domain_ids == [], do: "", else: "?domain_ids=" <> Enum.join(domain_ids, ",")

    %{
      title: "Hive · Drops",
      atom_href: "/drops/atom.xml" <> query,
      rss_href: "/drops/rss.xml" <> query
    }
  end

  defp parse_domain_ids(nil), do: []

  defp parse_domain_ids(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_domain_ids(_value), do: []

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

  defp define_filters(domains) do
    domain_options =
      domains
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    domain_display_names =
      Map.new(domains, fn domain -> {domain.id, domain.name} end)

    [
      %Filter.Filter{
        id: "domain",
        display_name: "Domain",
        type: :option,
        options: domain_options,
        options_display_names: domain_display_names,
        operator: :==,
        searchable: true,
        value: nil
      },
      %Filter.Filter{
        id: "source_type",
        display_name: "Source",
        type: :option,
        options: ["github_release", "rss"],
        options_display_names: %{
          "github_release" => "GitHub release",
          "rss" => "RSS"
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

  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M:%S UTC")
  defp format_datetime(_other), do: "-"

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_date(_other), do: "-"

  defp truncate(nil), do: nil
  defp truncate(body) when is_binary(body), do: Markdown.preview(body, 140)

  defp domain_chips([]), do: "Unclassified"
  defp domain_chips(nil), do: "Unclassified"
  defp domain_chips(domains), do: Enum.map_join(domains, ", ", & &1.name)

  defp project_chips([]), do: "—"
  defp project_chips(nil), do: "—"

  defp project_chips(domains) do
    domains
    |> Enum.map(fn domain -> domain.project && domain.project.name end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> "—"
      names -> Enum.join(names, ", ")
    end
  end
end

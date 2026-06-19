defmodule HiveWeb.DropsLive.Index do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  import Noora.Filter

  alias Hive.Drops
  alias Hive.Meadows
  alias HiveWeb.Endpoint
  alias HiveWeb.Layouts
  alias HiveWeb.Markdown
  alias HiveWeb.OpenGraph
  alias HiveWeb.Utilities.Query
  alias Noora.Filter

  @page_size 10

  def open_graph do
    %{
      description:
        "Shipped updates from GitHub releases and changelog feeds across every meadow.",
      eyebrow: "Drops",
      highlights: ["GitHub releases", "RSS / Atom changelogs", "Subscribe per meadow"],
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
     |> assign(:meadows, [])
     |> assign(:query, "")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign(:uri, URI.parse("/drops"))
     |> assign(:atom_feed, %{
       title: "Hive · Drops",
       atom_href: "/drops/atom.xml",
       rss_href: "/drops/rss.xml"
     })
     |> assign(:subscribe_meadow_ids, MapSet.new())
     |> assign(OpenGraph.assigns(open_graph()))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    user = socket.assigns[:current_user]
    meadows = Meadows.list_visible_meadows(user)
    available_filters = define_filters(meadows)
    query_params = Query.query_params(uri)

    page = Query.parse_page(params["page"])
    query = params["q"] || ""
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    {drops, meta} =
      Drops.list_drops(list_opts(user, query, active_filters, page))

    socket =
      socket
      |> assign(:uri, uri_from_query_params(query_params))
      |> assign(:meadows, meadows)
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

  def handle_event("toggle_subscribe_meadow", %{"data" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.subscribe_meadow_ids, id) do
        MapSet.delete(socket.assigns.subscribe_meadow_ids, id)
      else
        MapSet.put(socket.assigns.subscribe_meadow_ids, id)
      end

    {:noreply, assign(socket, :subscribe_meadow_ids, selected)}
  end

  def handle_event("clear_subscribe_meadows", _params, socket) do
    {:noreply, assign(socket, :subscribe_meadow_ids, MapSet.new())}
  end

  def handle_event("close_subscribe", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "subscribe-modal"})}
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
            <p>Shipped updates from GitHub releases and changelog feeds across every meadow.</p>
          </div>
          <div data-part="header-actions">
            <.subscribe_modal
              meadows={@meadows}
              selected_ids={@subscribe_meadow_ids}
              endpoint_url={endpoint_url()}
            />
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
              <:col :let={drop} label="Meadows">
                <.text_cell label={meadow_chips(drop.meadows)} />
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
    meadow_ids = parse_meadow_ids(params["meadow_ids"])
    query = if meadow_ids == [], do: "", else: "?meadow_ids=" <> Enum.join(meadow_ids, ",")

    %{
      title: "Hive · Drops",
      atom_href: "/drops/atom.xml" <> query,
      rss_href: "/drops/rss.xml" <> query
    }
  end

  defp parse_meadow_ids(nil), do: []

  defp parse_meadow_ids(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_meadow_ids(_value), do: []

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
    |> put_meadow_filter(active_filters)
    |> put_source_type_filter(active_filters)
  end

  defp put_meadow_filter(opts, active_filters) do
    case Enum.find(active_filters, &(&1.id == "meadow")) do
      %{operator: :==, value: value} when is_binary(value) and value != "" ->
        Keyword.put(opts, :meadow_ids, [value])

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

  defp define_filters(meadows) do
    meadow_options =
      meadows
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    meadow_display_names =
      Map.new(meadows, fn meadow -> {meadow.id, meadow.name} end)

    [
      %Filter.Filter{
        id: "meadow",
        display_name: "Meadow",
        type: :option,
        options: meadow_options,
        options_display_names: meadow_display_names,
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

  defp meadow_chips([]), do: "Unclassified"
  defp meadow_chips(nil), do: "Unclassified"
  defp meadow_chips(meadows), do: Enum.map_join(meadows, ", ", & &1.name)

  defp endpoint_url, do: Endpoint.url()

  attr :meadows, :list, required: true
  attr :selected_ids, MapSet, required: true
  attr :endpoint_url, :string, required: true

  defp subscribe_modal(assigns) do
    assigns =
      assigns
      |> assign(
        :atom_url,
        feed_url(assigns.endpoint_url, "/drops/atom.xml", assigns.selected_ids)
      )
      |> assign(
        :rss_url,
        feed_url(assigns.endpoint_url, "/drops/rss.xml", assigns.selected_ids)
      )

    ~H"""
    <.modal
      id="subscribe-modal"
      title="Subscribe to drops"
      description="Pick the meadows you want updates from. Leave empty to subscribe to every meadow."
      header_type="icon"
      header_size="large"
      on_dismiss="close_subscribe"
    >
      <:trigger :let={attrs}>
        <.button label="Subscribe" size="medium" variant="secondary" {attrs}>
          <:icon_left><.icon name="rss" /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="rss" />
      </:header_icon>

      <div data-part="subscribe-modal-body">
        <div :if={@meadows == []} data-part="empty-meadows">
          <p>No meadows yet. Create one to start filtering subscriptions.</p>
        </div>

        <div :if={@meadows != []} data-part="meadow-picker">
          <div data-part="picker-row">
            <span data-part="picker-label">Meadows</span>
            <div data-part="picker-controls">
              <.dropdown
                id="subscribe-meadow-dropdown"
                size="medium"
                label={picker_trigger_label(@selected_ids, @meadows)}
              >
                <.dropdown_item
                  :for={meadow <- @meadows}
                  value={meadow.id}
                  label={meadow.name}
                  size="large"
                  description={meadow.description}
                  checked={MapSet.member?(@selected_ids, meadow.id)}
                  on_click="toggle_subscribe_meadow"
                />
              </.dropdown>
              <.button
                :if={MapSet.size(@selected_ids) > 0}
                label="Clear"
                variant="secondary"
                size="medium"
                phx-click="clear_subscribe_meadows"
              />
            </div>
          </div>
        </div>

        <.line_divider />

        <div data-part="feed-urls">
          <div data-part="feed-url-row">
            <span data-part="feed-url-label">Atom</span>
            <div data-part="read-only-value">
              <code>{@atom_url}</code>
              <.button
                id="copy-atom-url"
                variant="secondary"
                size="small"
                icon_only
                type="button"
                phx-hook="Clipboard"
                data-clipboard-value={@atom_url}
                aria-label="Copy Atom feed URL"
              >
                <.icon name="copy" />
              </.button>
            </div>
          </div>
          <div data-part="feed-url-row">
            <span data-part="feed-url-label">RSS</span>
            <div data-part="read-only-value">
              <code>{@rss_url}</code>
              <.button
                id="copy-rss-url"
                variant="secondary"
                size="small"
                icon_only
                type="button"
                phx-hook="Clipboard"
                data-clipboard-value={@rss_url}
                aria-label="Copy RSS feed URL"
              >
                <.icon name="copy" />
              </.button>
            </div>
          </div>
        </div>
      </div>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label="Done"
              variant="primary"
              size="medium"
              type="button"
              phx-click="close_subscribe"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp picker_trigger_label(selected_ids, meadows) do
    case MapSet.size(selected_ids) do
      0 -> "All meadows"
      1 -> selected_meadow_name(selected_ids, meadows)
      n -> "#{n} selected"
    end
  end

  defp selected_meadow_name(selected_ids, meadows) do
    [id] = MapSet.to_list(selected_ids)

    case Enum.find(meadows, &(&1.id == id)) do
      %{name: name} -> name
      _ -> "1 selected"
    end
  end

  defp feed_url(endpoint, path, selected_ids) do
    case Enum.sort(MapSet.to_list(selected_ids)) do
      [] -> endpoint <> path
      ids -> endpoint <> path <> "?meadow_ids=" <> Enum.join(ids, ",")
    end
  end
end

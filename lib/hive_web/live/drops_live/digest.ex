defmodule HiveWeb.DropsLive.Digest do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  import Noora.Filter

  alias Hive.Drops.WeeklyDigest
  alias Hive.Drops.WeeklyDigests
  alias HiveWeb.Layouts
  alias HiveWeb.Markdown
  alias HiveWeb.OpenGraph
  alias HiveWeb.Utilities.Query
  alias Noora.Filter

  @page_size 10

  def open_graph(nil) do
    %{
      description:
        dgettext(
          "dashboard_drops",
          "Browse narrated weekly editions connecting the most meaningful updates shipped across Hive."
        ),
      section_label: dgettext("dashboard_drops", "Drops"),
      highlights: [
        dgettext("dashboard_drops", "Weekly editions"),
        dgettext("dashboard_drops", "Narrated"),
        dgettext("dashboard_drops", "Subscribable")
      ],
      id: "drops-weekly-digests",
      path: "/drops/digest",
      title: dgettext("dashboard_drops", "Weekly digests")
    }
  end

  def open_graph(%WeeklyDigest{} = digest) do
    %{
      description: digest.summary,
      section_label: dgettext("dashboard_drops", "Drops weekly digest"),
      highlights: [
        format_week(digest),
        drop_count_label(length(digest.drop_ids)),
        dgettext("dashboard_drops", "Narrated edition")
      ],
      id: "drops-weekly-digest-#{Date.to_iso8601(digest.week_start)}",
      path: WeeklyDigests.public_path(digest),
      title: digest.title
    }
  end

  def slack_unfurl(uri, params) do
    case Map.fetch(params, "week") do
      {:ok, week} ->
        case WeeklyDigests.fetch_published(week) do
          {:ok, digest} -> Hive.Slack.Unfurl.BlockKit.open_graph(uri, open_graph(digest))
          {:error, :not_found} -> :skip
        end

      :error ->
        Hive.Slack.Unfurl.BlockKit.open_graph(uri, open_graph(nil))
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_mode, :index)
     |> assign(:digest, nil)
     |> assign(:digests, [])
     |> assign(:digests_meta, empty_meta())
     |> assign(:available_filters, [])
     |> assign(:active_filters, [])
     |> assign(:query, "")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign(:uri, URI.parse("/drops/digest"))
     |> assign(:atom_feed, atom_feed())}
  end

  @impl true
  def handle_params(%{"week" => week}, _uri, socket) do
    case WeeklyDigests.fetch_published(week) do
      {:ok, digest} ->
        {:noreply, assign_detail(socket, digest)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("dashboard_drops", "Weekly digest not found."))
         |> push_navigate(to: ~p"/drops/digest")}
    end
  end

  def handle_params(params, uri, socket) do
    years = WeeklyDigests.published_years()
    available_filters = define_filters(years)
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)
    page = Query.parse_page(params["page"])
    query = params["q"] || ""

    {digests, meta} =
      WeeklyDigests.list_published_page(
        page: page,
        page_size: @page_size,
        query: Query.present_string(query),
        year: selected_year(active_filters)
      )

    {:noreply,
     socket
     |> assign(:page_mode, :index)
     |> assign(:page_title, page_title(socket, dgettext("dashboard_drops", "Weekly digests")))
     |> assign(:digest, nil)
     |> assign(:digests, digests)
     |> assign(:digests_meta, meta)
     |> assign(:available_filters, available_filters)
     |> assign(:active_filters, active_filters)
     |> assign(:query, query)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> assign(:uri, uri |> Query.query_params() |> uri_from_query_params())
     |> assign(OpenGraph.assigns(open_graph(nil)))}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/drops/digest?#{digest_query_params(query, socket.assigns.active_filters)}",
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
     |> push_patch(to: ~p"/drops/digest?#{updated_params}")
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
     |> push_patch(to: ~p"/drops/digest?#{updated_params}")
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
    >
      <section :if={@page_mode == :index} id="drops-digests">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{dgettext("dashboard_drops", "Weekly digests")}</h1>
            <p>
              {dgettext(
                "dashboard_drops",
                "Narrated editions connecting the most meaningful updates from each week."
              )}
            </p>
          </div>
          <div data-part="header-actions">
            <Layouts.feeds_dropdown
              id="drops-digest-feeds-dropdown"
              atom_href="/drops/digest/atom.xml"
              rss_href="/drops/digest/rss.xml"
            />
          </div>
        </div>

        <.card title={dgettext("dashboard_drops", "Editions")} icon="news">
          <.card_section>
            <div data-part="table-toolbar">
              <.filter_dropdown
                id="drops-digests-filter"
                label={dgettext("dashboard_drops", "Filter")}
                available_filters={@available_filters}
                active_filters={@active_filters}
                on_select="add_filter"
              />

              <div data-part="search">
                <.form
                  id="drops-digests-search-form"
                  for={@search_form}
                  phx-change="search"
                  phx-submit="search"
                >
                  <.text_input
                    id="drops-digests-search"
                    field={@search_form[:query]}
                    type="search"
                    show_suffix={false}
                    placeholder={dgettext("dashboard_drops", "Search editions...")}
                  />
                </.form>
              </div>
            </div>

            <div :if={@active_filters != []} data-part="active-filters">
              <.active_filter :for={filter <- @active_filters} filter={filter} />
            </div>

            <div data-part="table-scroll">
              <.table
                id="drops-digests-table"
                rows={@digests}
                row_key={fn digest -> "drops-digest-#{Date.to_iso8601(digest.week_start)}" end}
                row_navigate={&WeeklyDigests.public_path/1}
              >
                <:col :let={digest} label={dgettext("dashboard_drops", "Week")}>
                  <.text_cell label={format_week(digest)} />
                </:col>
                <:col :let={digest} label={dgettext("dashboard_drops", "Edition")}>
                  <.text_and_description_cell label={digest.title} description={digest.summary} />
                </:col>
                <:col :let={digest} label={dgettext("dashboard_drops", "Drops")}>
                  <.text_cell label={drop_count_label(length(digest.drop_ids))} />
                </:col>
                <:col :let={digest} label={dgettext("dashboard_drops", "Published")}>
                  <.text_cell label={format_published_at(digest.published_at)} />
                </:col>
                <:empty_state>
                  <.table_empty_state
                    icon="news"
                    title={dgettext("dashboard_drops", "No weekly digests found")}
                    subtitle={
                      dgettext(
                        "dashboard_drops",
                        "Adjust the filters or wait for the next narrated edition."
                      )
                    }
                  />
                </:empty_state>
              </.table>
            </div>

            <div :if={@digests_meta.total_pages > 1} data-part="pagination">
              <.button
                variant="secondary"
                label={dgettext("dashboard_drops", "Prev")}
                disabled={@digests_meta.current_page <= 1}
                patch={page_link(@uri, max(1, @digests_meta.current_page - 1))}
              >
                <:icon_left><.chevron_left /></:icon_left>
              </.button>
              <.button
                variant="secondary"
                label={dgettext("dashboard_drops", "Next")}
                disabled={@digests_meta.current_page >= @digests_meta.total_pages}
                patch={
                  page_link(
                    @uri,
                    min(@digests_meta.total_pages, @digests_meta.current_page + 1)
                  )
                }
              >
                <:icon_right><.chevron_right /></:icon_right>
              </.button>
            </div>
          </.card_section>
        </.card>
      </section>

      <section :if={@page_mode == :detail} id="drops-digest">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{dgettext("dashboard_drops", "Weekly digest")}</h1>
            <p>
              {dgettext(
                "dashboard_drops",
                "One connected story about what shipped during the week."
              )}
            </p>
          </div>
          <div data-part="header-actions">
            <Layouts.feeds_dropdown
              id="drops-digest-feeds-dropdown"
              atom_href="/drops/digest/atom.xml"
              rss_href="/drops/digest/rss.xml"
            />
            <.link navigate={~p"/drops/digest"}>
              <.button
                label={dgettext("dashboard_drops", "All digests")}
                size="medium"
                variant="secondary"
              >
                <:icon_left><.icon name="list_tree" /></:icon_left>
              </.button>
            </.link>
          </div>
        </div>

        <.card
          :if={@digest}
          title={dgettext("dashboard_drops", "Weekly edition")}
          icon="news"
          data-part="edition-card"
        >
          <.card_section>
            <article data-part="edition">
              <time datetime={Date.to_iso8601(@digest.week_start)} data-part="week">
                {format_week(@digest)}
              </time>
              <h2>{@digest.title}</h2>
              <p data-part="summary">{@digest.summary}</p>
              <div data-part="body">{Markdown.render(@digest.body)}</div>
              <p data-part="source-note">
                {dgettext(
                  "dashboard_drops",
                  "Narrated from %{count}.",
                  count: drop_count_label(length(@digest.drop_ids))
                )}
              </p>
            </article>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  defp assign_detail(socket, digest) do
    socket
    |> assign(:page_mode, :detail)
    |> assign(:page_title, page_title(socket, digest.title))
    |> assign(:digest, digest)
    |> assign(OpenGraph.assigns(open_graph(digest)))
  end

  defp page_title(socket, title) do
    dgettext("dashboard_drops", "%{title} · %{product}",
      title: title,
      product: socket.assigns.product_name
    )
  end

  defp atom_feed do
    %{
      title: dgettext("dashboard_drops", "Hive · Drops weekly digest"),
      atom_href: "/drops/digest/atom.xml",
      rss_href: "/drops/digest/rss.xml"
    }
  end

  defp empty_meta do
    %{current_page: 1, page_size: @page_size, total_entries: 0, total_pages: 1}
  end

  defp page_link(uri, page) do
    "?" <> Query.put(uri.query, "page", Integer.to_string(page))
  end

  defp digest_query_params(query, active_filters) do
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

  defp define_filters(years) do
    options = Enum.map(years, &Integer.to_string/1)

    case options do
      [] ->
        []

      options ->
        [
          %Filter.Filter{
            id: "year",
            display_name: dgettext("dashboard_drops", "Year"),
            type: :option,
            options: options,
            options_display_names: Map.new(options, &{&1, &1}),
            operator: :==,
            searchable: false,
            value: nil
          }
        ]
    end
  end

  defp selected_year(active_filters) do
    case Enum.find(active_filters, &(&1.id == "year")) do
      %{operator: :==, value: value} -> parse_year(value)
      _filter -> nil
    end
  end

  defp parse_year(value) when is_integer(value), do: value

  defp parse_year(value) when is_binary(value) do
    case Integer.parse(value) do
      {year, ""} when year > 0 -> year
      _invalid -> nil
    end
  end

  defp parse_year(_value), do: nil

  defp format_week(%WeeklyDigest{} = digest) do
    dgettext("dashboard_drops", "%{start} to %{end}",
      start: Calendar.strftime(digest.week_start, "%B %-d"),
      end: Calendar.strftime(digest.week_end, "%B %-d, %Y")
    )
  end

  defp format_published_at(%DateTime{} = published_at) do
    Calendar.strftime(published_at, "%B %-d, %Y")
  end

  defp format_published_at(_published_at), do: "-"

  defp drop_count_label(1), do: dgettext("dashboard_drops", "1 public drop")

  defp drop_count_label(count),
    do: dgettext("dashboard_drops", "%{count} public drops", count: count)
end

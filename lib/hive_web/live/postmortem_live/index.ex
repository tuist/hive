defmodule HiveWeb.PostmortemLive.Index do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Postmortems
  alias HiveWeb.Layouts
  alias HiveWeb.Markdown
  alias HiveWeb.OpenGraph
  alias HiveWeb.Utilities.Query
  alias Noora.Filter.Operations

  @page_size 20

  def open_graph(postmortems) do
    %{
      description:
        dgettext(
          "dashboard_postmortems",
          "Published accounts of incidents and what we learned from them."
        ),
      section_label: dgettext("dashboard_postmortems", "Postmortems"),
      highlights: [
        dgettext("dashboard_postmortems", "%{count} postmortems", count: length(postmortems))
      ],
      id: "postmortems",
      path: "/postmortems",
      title: dgettext("dashboard_postmortems", "Postmortems")
    }
  end

  def slack_unfurl(uri, _params),
    do: Hive.Slack.Unfurl.BlockKit.open_graph(uri, open_graph(Postmortems.list_postmortems()))

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       :page_title,
       dgettext("dashboard_postmortems", "Postmortems · %{product}",
         product: socket.assigns.product_name
       )
     )
     |> assign(OpenGraph.assigns(open_graph([])))
     |> assign(:atom_feed, %{
       title: dgettext("dashboard_postmortems", "Hive · Postmortems"),
       atom_href: "/postmortems/atom.xml",
       rss_href: "/postmortems/rss.xml"
     })
     |> assign(:available_filters, available_filters())
     |> assign(:active_filters, [])
     |> assign(:uri, URI.parse("/postmortems"))
     |> assign(:query, "")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign(:postmortems, [])
     |> assign(:postmortems_meta, %{current_page: 1, total_pages: 1, total_entries: 0})
     |> assign(:can_publish?, Postmortems.can_publish?(socket.assigns.current_user))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    active_filters =
      Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    query = params |> Map.get("q", "") |> String.trim()
    page = params |> Map.get("page", "1") |> parse_page()

    {postmortems, postmortems_meta} =
      Postmortems.list_postmortems_page(
        page: page,
        page_size: @page_size,
        query: query,
        published: published_filter(active_filters),
        user: socket.assigns.current_user
      )

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:active_filters, active_filters)
     |> assign(:query, query)
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> assign(:postmortems, postmortems)
     |> assign(:postmortems_meta, postmortems_meta)
     |> assign(OpenGraph.assigns(open_graph(postmortems)))}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    params =
      socket.assigns.active_filters
      |> Operations.encode_filters_to_query()
      |> Query.put_present("q", String.trim(query))

    {:noreply, push_patch(socket, to: ~p"/postmortems?#{params}", replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    params = Operations.add_filter_to_query(filter_id, socket)
    {:noreply, push_patch(socket, to: ~p"/postmortems?#{params}")}
  end

  def handle_event("update_filter", params, socket) do
    params = Operations.update_filters_in_query(params, socket)
    {:noreply, push_patch(socket, to: ~p"/postmortems?#{params}")}
  end

  defp available_filters do
    [
      %Noora.Filter.Filter{
        id: "published",
        field: :published,
        display_name: dgettext("dashboard_postmortems", "Published"),
        type: :option,
        options: [:last_30_days],
        options_display_names: %{last_30_days: dgettext("dashboard_postmortems", "Last 30 days")},
        operator: :==,
        value: :last_30_days
      }
    ]
  end

  defp published_filter(active_filters) do
    case Enum.find(active_filters, &(&1.id == "published")) do
      %{operator: :==, value: :last_30_days} -> :last_30_days
      _filter -> nil
    end
  end

  defp parse_page(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _invalid -> 1
    end
  end

  defp page_link(uri, page), do: "?" <> Query.put(uri.query, "page", page)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard flash={@flash} product_name={@product_name} user_name={@user_name} user_email={@user_email} avatar_color={@avatar_color} auth_enabled?={@auth_enabled?} signed_in?={@signed_in?} admin?={@admin?}
      member?={@member?} csrf_token={@csrf_token} current_path={@current_path} forage_sources={@forage_sources} specs_have_new_activity?={@specs_have_new_activity?}>
      <section id="postmortems">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{dgettext("dashboard_postmortems", "Postmortems")}</h1>
            <p>{dgettext("dashboard_postmortems", "Published accounts of incidents and what we learned from them.")}</p>
          </div>
          <div data-part="header-actions">
            <Layouts.feeds_dropdown id="postmortems-feeds-dropdown" atom_href="/postmortems/atom.xml" rss_href="/postmortems/rss.xml" />
            <.button :if={@can_publish?} label={dgettext("dashboard_postmortems", "Publish postmortem")} href={~p"/postmortems/new"} size="medium" variant="primary"><:icon_left><.circle_plus /></:icon_left></.button>
          </div>
        </div>
        <.card icon="alert_triangle" title={dgettext("dashboard_postmortems", "Postmortems")}>
          <.card_section>
            <div data-part="table-toolbar">
              <.filter_dropdown id="postmortems-filter" label={dgettext("dashboard_postmortems", "Filter")} available_filters={@available_filters} active_filters={@active_filters} on_select="add_filter" />
              <div data-part="search">
                <.form id="postmortems-search-form" for={@search_form} phx-change="search" phx-submit="search">
                  <.text_input id="postmortems-search" field={@search_form[:query]} type="search" show_suffix={false} placeholder={dgettext("dashboard_postmortems", "Search postmortems...")} />
                </.form>
              </div>
            </div>
            <div :if={@active_filters != []} data-part="active-filters"><.active_filter :for={filter <- @active_filters} filter={filter} /></div>
            <div :if={@postmortems == []} data-part="empty-state">
              <div data-part="empty-icon"><.icon name="alert_triangle" /></div>
              <h2>{dgettext("dashboard_postmortems", "No postmortems yet")}</h2>
              <p>{dgettext("dashboard_postmortems", "Published postmortems will appear here.")}</p>
            </div>
            <.table :if={@postmortems != []} id="postmortems-table" rows={@postmortems} row_navigate={fn postmortem -> ~p"/postmortems/#{postmortem.number}" end}>
              <:col :let={postmortem} label={dgettext("dashboard_postmortems", "Postmortem")}><.text_and_description_cell label={dgettext("dashboard_postmortems", "#%{number} %{title}", number: postmortem.number, title: Postmortems.title(postmortem))} description={Markdown.preview(postmortem.body)} icon="alert_triangle" /></:col>
              <:col :let={postmortem} label={dgettext("dashboard_postmortems", "Author")}>
                <div data-part="author-cell">
                  <.text_and_description_cell label={author_name(postmortem)}>
                    <:image>
                      <.avatar
                        id={"postmortem-author-#{postmortem.id}"}
                        name={author_name(postmortem)}
                        color={avatar_color(author_name(postmortem))}
                        size="small"
                      />
                    </:image>
                  </.text_and_description_cell>
                </div>
              </:col>
              <:col :let={postmortem} label={dgettext("dashboard_postmortems", "Published")}><.time_cell time={postmortem.inserted_at} /></:col>
            </.table>
            <div :if={@postmortems_meta.total_pages > 1} data-part="pagination">
              <.button variant="secondary" label={dgettext("dashboard_postmortems", "Prev")} disabled={@postmortems_meta.current_page <= 1} patch={page_link(@uri, max(1, @postmortems_meta.current_page - 1))}><:icon_left><.chevron_left /></:icon_left></.button>
              <.button variant="secondary" label={dgettext("dashboard_postmortems", "Next")} disabled={@postmortems_meta.current_page >= @postmortems_meta.total_pages} patch={page_link(@uri, min(@postmortems_meta.total_pages, @postmortems_meta.current_page + 1))}><:icon_right><.chevron_right /></:icon_right></.button>
            </div>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  defp author_name(%{created_by_user: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp author_name(%{created_by_user: %{email: email}}) when is_binary(email), do: email
  defp author_name(_postmortem), do: dgettext("dashboard_postmortems", "Unknown")

  defp avatar_color(author) do
    colors = ~w(gray red orange yellow azure blue purple pink)
    Enum.at(colors, :erlang.phash2(author, length(colors)))
  end
end

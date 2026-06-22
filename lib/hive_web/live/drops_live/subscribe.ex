defmodule HiveWeb.DropsLive.Subscribe do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  import Noora.CheckboxControl

  alias Hive.Domains
  alias HiveWeb.Endpoint
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description:
        "Subscribe to Hive drops via Atom or RSS. Pick the domains you want updates from and copy the matching feed URL.",
      section_label: "Drops",
      highlights: ["Atom 1.0", "RSS 2.0", "Per-domain filtering"],
      id: "drops-subscribe",
      path: "/drops/subscribe",
      title: "Subscribe to drops"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    domains = Domains.list_visible_domains(socket.assigns[:current_user])

    {:ok,
     socket
     |> assign(:page_title, "Subscribe to drops · #{socket.assigns.product_name}")
     |> assign(:domains, domains)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:atom_feed, %{
       title: "Hive · Drops",
       atom_href: "/drops/atom.xml",
       rss_href: "/drops/rss.xml"
     })
     |> assign(OpenGraph.assigns(open_graph()))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected =
      params["domain_ids"]
      |> parse_domain_ids()
      |> MapSet.new()

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("toggle_domain", %{"data" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:atom_url, feed_url("/drops/atom.xml", assigns.selected_ids))
      |> assign(:rss_url, feed_url("/drops/rss.xml", assigns.selected_ids))

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
      <section id="drops-subscribe">
        <div data-part="page-header">
          <div data-part="title-group">
            <.badge label="Drops" color="information" style="light-fill" />
            <h1>Subscribe to drops</h1>
            <p>
              Pick the domains you want updates from and copy the matching Atom or RSS URL into
              your reader. Leave the picker empty to subscribe to every domain on this instance.
            </p>
          </div>
        </div>

        <.card title="Feed URLs" icon="external_link">
          <.card_section>
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
                    data-part="copy-button"
                  >
                    <span data-part="copy-icon"><.icon name="copy" /></span>
                    <span data-part="copy-check-icon"><.icon name="copy_check" /></span>
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
                    data-part="copy-button"
                  >
                    <span data-part="copy-icon"><.icon name="copy" /></span>
                    <span data-part="copy-check-icon"><.icon name="copy_check" /></span>
                  </.button>
                </div>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card title="Domains" icon="rss">
          <:actions :if={MapSet.size(@selected_ids) > 0}>
            <.button
              label="Clear"
              variant="secondary"
              size="medium"
              phx-click="clear"
            />
          </:actions>

          <.card_section>
            <div data-part="domains-card-body">
              <p data-part="picker-help">
                Tick the domains you want updates from. Leave them all unchecked to subscribe to every domain on this instance.
              </p>

              <p :if={@domains == []} data-part="empty">
                No domains yet. Create one to start filtering subscriptions.
              </p>

              <.table :if={@domains != []} id="subscribe-domains-table" rows={@domains}>
              <:col :let={domain} label="Domain">
                <label
                  id={"subscribe-domain-row-#{domain.id}"}
                  data-part="domain-row"
                  phx-click="toggle_domain"
                  phx-value-data={domain.id}
                >
                  <.checkbox_control checked={MapSet.member?(@selected_ids, domain.id)} />
                  <.text_and_description_cell
                    label={domain.name}
                    description={domain.description || "—"}
                  />
                </label>
              </:col>
            </.table>
            </div>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  defp feed_url(path, selected_ids) do
    case Enum.sort(MapSet.to_list(selected_ids)) do
      [] -> Endpoint.url() <> path
      ids -> Endpoint.url() <> path <> "?domain_ids=" <> Enum.join(ids, ",")
    end
  end

  defp parse_domain_ids(nil), do: []

  defp parse_domain_ids(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_domain_ids(_), do: []
end

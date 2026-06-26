defmodule HiveWeb.DropsLive.Show do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  alias Hive.Drops
  alias HiveWeb.Layouts
  alias HiveWeb.Markdown
  alias HiveWeb.OpenGraph

  def open_graph(drop) do
    %{
      description: description(drop),
      section_label: section_label(drop),
      highlights: highlights(drop),
      id: "drop-#{drop.number}",
      path: Drops.public_path(drop),
      title: drop.title
    }
  end

  @impl true
  def mount(%{"number" => reference}, _session, socket) do
    user = socket.assigns[:current_user]

    case Drops.fetch_visible_drop(reference, user) do
      {:ok, drop} ->
        if reference == to_string(drop.number) do
          {:ok,
           socket
           |> assign(:page_title, "#{drop.title} · #{socket.assigns.product_name}")
           |> assign(:drop, drop)
           |> assign(:atom_feed, %{
             title: "Hive · Drops",
             atom_href: "/drops/atom.xml",
             rss_href: "/drops/rss.xml"
           })
           |> assign(OpenGraph.assigns(open_graph(drop)))}
        else
          {:ok, redirect(socket, to: Drops.public_path(drop))}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Drop not found.")
         |> redirect(to: ~p"/drops")}
    end
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
      <section id="drop-show">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{Markdown.inline(@drop.title)}</h1>
          </div>
          <div data-part="header-actions">
            <.button
              :if={@drop.url}
              label="Open original"
              variant="secondary"
              href={@drop.url}
              target="_blank"
              rel="noreferrer noopener"
            >
              <:icon_right><.icon name="external_link" /></:icon_right>
            </.button>
          </div>
        </div>

        <.card title="Metadata" icon="package" data-part="metadata-card">
          <.card_section data-part="metadata-card-section">
            <div data-part="metadata-grid">
              <div data-part="metadata-row">
                <div data-part="metadata">
                  <div data-part="title">Source</div>
                  <span data-part="label">{Drops.source_type_label(@drop.source_type)}</span>
                </div>
                <div :if={@drop.version} data-part="metadata">
                  <div data-part="title">Version</div>
                  <span data-part="version">{@drop.version}</span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">Domains</div>
                  <div :if={drop_domains(@drop) != []} data-part="metadata-badges">
                    <.link
                      :for={domain <- drop_domains(@drop)}
                      navigate={~p"/domains/#{domain.id}"}
                      data-part="domain-link"
                    >
                      {domain.name}
                    </.link>
                  </div>
                  <span :if={drop_domains(@drop) == []} data-part="label">Unclassified</span>
                </div>
              </div>

              <div data-part="metadata-row">
                <div :if={@drop.published_at} data-part="metadata">
                  <div data-part="title">Published</div>
                  <span data-part="label">
                    {Calendar.strftime(@drop.published_at, "%b %d, %Y · %H:%M UTC")}
                  </span>
                </div>
                <div :if={@drop.github_repository} data-part="metadata">
                  <div data-part="title">Repository</div>
                  <span data-part="label">
                    {@drop.github_repository.owner}/{@drop.github_repository.name}
                  </span>
                </div>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card title="Update" icon="package">
          <.card_section>
            <article :if={present?(@drop.body)} data-part="body">
              {Markdown.render(@drop.body)}
            </article>
            <div :if={!present?(@drop.body)} data-part="empty-body">
              <p>No body for this drop. Use the “Open original” link to read the source.</p>
            </div>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  defp description(drop) do
    case drop.body do
      nil -> "Shipped update from the #{domain_name(drop)} domain."
      body -> Markdown.preview(body, 180)
    end
  end

  defp section_label(drop) do
    parts =
      [
        Drops.source_type_label(drop.source_type),
        drop.version
      ]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    Enum.join(parts, " · ")
  end

  defp highlights(drop) do
    [
      domain_name(drop),
      drop.version,
      Drops.source_type_label(drop.source_type)
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
  end

  defp domain_name(%{domains: [%{name: name} | _]}), do: name
  defp domain_name(_drop), do: "Unclassified"

  defp drop_domains(%{domains: domains}) when is_list(domains), do: domains
  defp drop_domains(_drop), do: []

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_other), do: false
end

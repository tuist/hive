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
      eyebrow: eyebrow(drop),
      highlights: highlights(drop),
      id: "drop-#{drop.id}",
      path: "/drops/#{drop.id}",
      title: drop.title
    }
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns[:current_user]

    case Drops.fetch_visible_drop(id, user) do
      {:ok, drop} ->
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
            <div data-part="eyebrow">
              <.badge label="Drop" color="information" style="light-fill" />
              <.badge
                label={Drops.source_type_label(@drop.source_type)}
                color={source_badge_color(@drop.source_type)}
                style="light-fill"
              />
              <span :if={@drop.version} data-part="version">{@drop.version}</span>
            </div>
            <h1>{Markdown.inline(@drop.title)}</h1>
            <div data-part="meta">
              <span :for={meadow <- @drop.meadows || []}>
                <.link navigate={~p"/meadows/#{meadow.id}"} data-part="meadow-link">
                  {meadow.name}
                </.link>
              </span>
              <span :if={(@drop.meadows || []) == []}>Unclassified</span>
              <span :if={@drop.published_at}>
                {Calendar.strftime(@drop.published_at, "%b %d, %Y · %H:%M UTC")}
              </span>
              <span :if={@drop.github_repository}>
                {@drop.github_repository.owner}/{@drop.github_repository.name}
              </span>
            </div>
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
      nil -> "Shipped update from the #{meadow_name(drop)} meadow."
      body -> Markdown.preview(body, 180)
    end
  end

  defp eyebrow(drop) do
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
      meadow_name(drop),
      drop.version,
      Drops.source_type_label(drop.source_type)
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
  end

  defp meadow_name(%{meadows: [%{name: name} | _]}), do: name
  defp meadow_name(_drop), do: "Unclassified"

  defp source_badge_color(:github_release), do: "focus"
  defp source_badge_color(:rss), do: "information"
  defp source_badge_color(_other), do: "neutral"

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_other), do: false
end

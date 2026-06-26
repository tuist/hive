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
           |> assign(
             :page_title,
             dgettext("dashboard_drops", "%{title} · %{product}",
               title: drop.title,
               product: socket.assigns.product_name
             )
           )
           |> assign(:drop, drop)
           |> assign(:atom_feed, %{
             title: dgettext("dashboard_drops", "Hive · Drops"),
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
         |> put_flash(:error, dgettext("dashboard_drops", "Drop not found."))
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
              label={dgettext("dashboard_drops", "Open original")}
              variant="secondary"
              href={@drop.url}
              target="_blank"
              rel="noreferrer noopener"
            >
              <:icon_right><.icon name="external_link" /></:icon_right>
            </.button>
          </div>
        </div>

        <.card title={dgettext("dashboard_drops", "Metadata")} icon="package" data-part="metadata-card">
          <.card_section data-part="metadata-card-section">
            <div data-part="metadata-grid">
              <div data-part="metadata-row">
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_drops", "Source")}</div>
                  <span data-part="label">{Drops.source_type_label(@drop.source_type)}</span>
                </div>
                <div :if={@drop.version} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_drops", "Version")}</div>
                  <span data-part="version">{@drop.version}</span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_drops", "Domains")}</div>
                  <div :if={drop_domains(@drop) != []} data-part="metadata-badges">
                    <.link
                      :for={domain <- drop_domains(@drop)}
                      navigate={~p"/domains/#{domain.id}"}
                      data-part="domain-link"
                    >
                      {domain.name}
                    </.link>
                  </div>
                  <span :if={drop_domains(@drop) == []} data-part="label">
                    {dgettext("dashboard_drops", "Unclassified")}
                  </span>
                </div>
              </div>

              <div data-part="metadata-row">
                <div :if={@drop.published_at} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_drops", "Published")}</div>
                  <span data-part="label">
                    {Calendar.strftime(@drop.published_at, "%b %d, %Y · %H:%M UTC")}
                  </span>
                </div>
                <div :if={@drop.github_repository} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_drops", "Repository")}</div>
                  <span data-part="label">
                    {@drop.github_repository.owner}/{@drop.github_repository.name}
                  </span>
                </div>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card title={dgettext("dashboard_drops", "Update")} icon="package">
          <.card_section>
            <article :if={present?(@drop.body)} data-part="body">
              {Markdown.render(@drop.body)}
            </article>
            <div :if={!present?(@drop.body)} data-part="empty-body">
              <p>
                {dgettext(
                  "dashboard_drops",
                  "No body for this drop. Use the Open original link to read the source."
                )}
              </p>
            </div>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  defp description(drop) do
    if present?(drop.body) do
      Markdown.preview(drop.body, 180)
    else
      case primary_context(drop) do
        nil ->
          dgettext("dashboard_drops", "Shipped update from %{source}.",
            source: source_card_label(drop.source_type)
          )

        context ->
          dgettext("dashboard_drops", "Shipped update for %{context} from %{source}.",
            context: context,
            source: source_card_label(drop.source_type)
          )
      end
    end
  end

  defp section_label(drop) do
    parts =
      [
        dgettext("dashboard_drops", "Drop"),
        source_card_label(drop.source_type),
        drop.version
      ]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    Enum.join(parts, " · ")
  end

  defp highlights(drop) do
    [
      project_context(drop),
      domain_context(drop),
      published_context(drop.published_at)
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> case do
      [] -> [source_card_label(drop.source_type)]
      highlights -> highlights
    end
  end

  defp source_card_label(:github_release), do: dgettext("dashboard_drops", "GitHub release")
  defp source_card_label(:rss), do: dgettext("dashboard_drops", "Changelog feed")
  defp source_card_label(_source_type), do: dgettext("dashboard_drops", "Drop")

  defp primary_context(drop) do
    case project_names(drop) do
      [name | _] -> name
      [] -> drop |> domain_names() |> List.first()
    end
  end

  defp project_context(drop) do
    drop
    |> project_names()
    |> context_label(
      dgettext("dashboard_drops", "Project"),
      dgettext("dashboard_drops", "Projects")
    )
  end

  defp domain_context(drop) do
    drop
    |> domain_names()
    |> context_label(
      dgettext("dashboard_drops", "Domain"),
      dgettext("dashboard_drops", "Domains")
    )
  end

  defp context_label([], _singular, _plural), do: nil

  defp context_label([name], singular, _plural),
    do: dgettext("dashboard_drops", "%{label}: %{name}", label: singular, name: name)

  defp context_label(names, _singular, plural) do
    dgettext("dashboard_drops", "%{label}: %{names}",
      label: plural,
      names: names |> Enum.take(2) |> Enum.join(", ")
    )
  end

  defp project_names(drop) do
    drop
    |> Drops.projects_for_drop()
    |> Enum.map(& &1.name)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
  end

  defp domain_names(%{domains: domains}) when is_list(domains) do
    domains
    |> Enum.map(& &1.name)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
  end

  defp domain_names(_drop), do: []

  defp published_context(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp published_context(_datetime), do: nil

  defp drop_domains(%{domains: domains}) when is_list(domains), do: domains
  defp drop_domains(_drop), do: []

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_other), do: false
end

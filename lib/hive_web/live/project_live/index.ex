defmodule HiveWeb.ProjectLive.Index do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  alias Hive.Projects
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description:
        "Projects are the products, codebases, and services this Hive tracks. Each project owns repositories, domains, and drop sources.",
      eyebrow: "Projects",
      highlights: ["Top-level grouping", "Owns repositories", "Owns domains"],
      id: "projects",
      path: "/projects",
      title: "Projects"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Projects · #{socket.assigns.product_name}")
     |> assign(:projects, Projects.list_visible_projects(socket.assigns[:current_user]))
     |> assign(OpenGraph.assigns(open_graph()))}
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
      <section id="projects">
        <div data-part="header">
          <div data-part="title-group">
            <.badge label="Projects" color="information" style="light-fill" />
            <h1>Projects</h1>
            <p>
              The products, codebases, and services this Hive instance tracks. Each project owns
              its connected GitHub repositories and the domains (sub-domains) the team slices by.
            </p>
          </div>
        </div>

        <.card title="All projects" icon="apps">
          <.card_section>
            <.table id="projects-table" rows={@projects}>
              <:col :let={project} label="Name">
                <.link navigate={~p"/projects/#{project.id}"} data-part="project-link">
                  <.text_and_description_cell
                    label={project.name}
                    description={project.description || "—"}
                  />
                </.link>
              </:col>
              <:col :let={project} label="Visibility">
                <.badge_cell
                  label={visibility_label(project.visibility)}
                  color={visibility_color(project.visibility)}
                  style="light-fill"
                />
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="apps"
                  title="No projects yet"
                  subtitle="Create one to start tracking releases and changelog updates."
                />
              </:empty_state>
            </.table>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  defp visibility_label(:public), do: "Public"
  defp visibility_label(:private), do: "Private"
  defp visibility_label(_), do: "—"

  defp visibility_color(:public), do: "success"
  defp visibility_color(:private), do: "attention"
  defp visibility_color(_), do: "neutral"
end

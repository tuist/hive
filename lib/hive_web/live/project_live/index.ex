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
     |> assign(
       :projects,
       socket.assigns[:current_user]
       |> Projects.list_visible_projects()
       |> order_projects()
     )
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
            <div :if={@projects == []} data-part="empty">
              <p>No projects yet. Create one to start tracking releases and changelog updates.</p>
            </div>

            <div :if={@projects != []} data-part="project-list">
              <.link
                :for={project <- @projects}
                navigate={~p"/projects/#{project.id}"}
                data-part="project-row"
              >
                <div data-part="project-copy">
                  <h2>{project.name}</h2>
                  <p>{project.description || "No description yet."}</p>
                </div>
                <div data-part="project-meta">
                  <.badge
                    label={visibility_label(project.visibility)}
                    color={visibility_color(project.visibility)}
                    style="light-fill"
                  />
                  <.chevron_right />
                </div>
              </.link>
            </div>
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

  defp order_projects(projects), do: Enum.sort_by(projects, &project_order/1)

  defp project_order(%{name: "Tuist"}), do: {0, "Tuist"}
  defp project_order(%{name: "Atlas"}), do: {1, "Atlas"}
  defp project_order(%{name: "Hive"}), do: {2, "Hive"}
  defp project_order(%{name: "Once"}), do: {3, "Once"}
  defp project_order(project), do: {4, String.downcase(project.name)}
end

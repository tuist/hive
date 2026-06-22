defmodule HiveWeb.ProjectLive.Show do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  alias Hive.Projects
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph(project) do
    %{
      description:
        project.description ||
          "Repositories, domains, and drop sources tracked under the #{project.name} project.",
      section_label: "Project",
      highlights: [
        project.name,
        "#{length(project.domains)} domains",
        "#{length(project.github_repositories)} repositories"
      ],
      id: "project-#{project.id}",
      path: "/projects/#{project.id}",
      title: project.name
    }
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Projects.fetch_visible_project(id, socket.assigns[:current_user]) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(:page_title, "#{project.name} · Projects · #{socket.assigns.product_name}")
         |> assign(:project, project)
         |> assign(OpenGraph.assigns(open_graph(project)))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> redirect(to: ~p"/projects")}
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
      <section id="project-show">
        <div data-part="header">
          <div data-part="title-group">
            <.badge label="Project" color="information" style="light-fill" />
            <h1>{@project.name}</h1>
            <p :if={@project.description}>{@project.description}</p>
          </div>
        </div>

        <.card title="Repositories" icon="brand_github">
          <.card_section>
            <div :if={@project.github_repositories == []} data-part="empty">
              <p>No repositories connected yet.</p>
            </div>
            <ul :if={@project.github_repositories != []} data-part="repo-list">
              <li :for={repo <- @project.github_repositories}>
                <.badge label={"#{repo.owner}/#{repo.name}"} color="neutral" style="light-fill">
                  <:icon><.brand_github /></:icon>
                </.badge>
              </li>
            </ul>
          </.card_section>
        </.card>

        <.card title="Domains" icon="treemap">
          <.card_section>
            <div :if={@project.domains == []} data-part="empty">
              <p>No domains defined. Drops from this project will appear as Unclassified.</p>
            </div>
            <ul :if={@project.domains != []} data-part="domain-list">
              <li :for={domain <- @project.domains}>
                <.link navigate={~p"/domains/#{domain.id}"} data-part="domain-link">
                  <.badge label={domain.name} color="information" style="light-fill" />
                </.link>
              </li>
            </ul>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end
end

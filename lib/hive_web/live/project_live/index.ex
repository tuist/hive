defmodule HiveWeb.ProjectLive.Index do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  alias Hive.Auth
  alias Hive.Projects
  alias Hive.Projects.Project
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description:
        "Projects are the products, codebases, and services this Hive tracks. Each project owns repositories and sources, and links to reusable domains.",
      section_label: "Projects",
      highlights: ["Top-level grouping", "Owns repositories", "Reusable domains"],
      id: "projects",
      path: "/projects",
      title: "Projects"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]
    editable? = Auth.member?(user)

    {:ok,
     socket
     |> assign(:page_title, "Projects · #{socket.assigns.product_name}")
     |> assign(:editable?, editable?)
     |> assign(:projects, list_projects(user))
     |> assign_project_form(Projects.change_project())
     |> assign(OpenGraph.assigns(open_graph()))}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      %Project{}
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_project_form(socket, changeset)}
  end

  def handle_event("create", %{"project" => params}, socket) do
    if socket.assigns.editable? do
      create_project(socket, params)
    else
      {:noreply, put_flash(socket, :error, "Only organization members can create projects.")}
    end
  end

  def handle_event("cancel_new_project", _params, socket) do
    {:noreply,
     socket
     |> assign_project_form(Projects.change_project())
     |> push_event("close-modal", %{id: "new-project-modal"})
     |> push_event("reset-form", %{id: "new-project-form"})}
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
            <h1>Projects</h1>
            <p>
              The products, codebases, and services this Hive instance tracks. Each project owns
              its linked GitHub repositories and can link to the domains the team slices by.
            </p>
          </div>
          <div :if={@editable?} data-part="header-actions">
            <.new_project_modal form={@project_form} />
          </div>
        </div>

        <.card title="All projects" icon="apps">
          <.card_section>
            <div data-part="projects-table">
              <.table
                id="projects-table"
                rows={@projects}
                row_key={fn project -> "project-#{project.id || project.name}" end}
              >
                <:col :let={project} label="Project">
                  <div data-part="cell" data-type="text_and_description">
                    <div data-part="column">
                      <.link navigate={~p"/projects/#{project.id}"} data-part="project-title-link">
                        <span data-part="label">{project.name}</span>
                      </.link>
                      <span data-part="description">
                        {project.description || "No description yet."}
                      </span>
                    </div>
                  </div>
                </:col>
                <:col :let={project} label="Visibility">
                  <div data-part="cell" data-type="badge">
                    <.badge
                      label={visibility_label(project.visibility)}
                      color={visibility_color(project.visibility)}
                      style="light-fill"
                      size="large"
                    >
                      <:icon>
                        <.lock :if={project.visibility == :private} />
                        <.world :if={project.visibility != :private} />
                      </:icon>
                    </.badge>
                  </div>
                </:col>
                <:col :let={project} label="Feed">
                  <div :if={project.id} data-part="cell" data-type="feed">
                    <a
                      href={"/projects/#{project.id}/drops/atom.xml"}
                      data-part="feed-link"
                      title="Subscribe via Atom"
                    >
                      <.icon name="rss" /><span>Atom</span>
                    </a>
                    <a
                      href={"/projects/#{project.id}/drops/rss.xml"}
                      data-part="feed-link"
                      title="Subscribe via RSS"
                    >
                      <.icon name="rss" /><span>RSS</span>
                    </a>
                  </div>
                </:col>
                <:empty_state>
                  <.table_empty_state
                    icon="apps"
                    title="No projects yet"
                    subtitle="Create one to start tracking releases and changelog updates."
                  />
                </:empty_state>
              </.table>
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

  defp create_project(socket, params) do
    case Projects.create_project(params) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created.")
         |> assign(:projects, list_projects(socket.assigns[:current_user]))
         |> assign_project_form(Projects.change_project())
         |> push_event("close-modal", %{id: "new-project-modal"})
         |> push_event("reset-form", %{id: "new-project-form"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign_project_form(Map.put(changeset, :action, :insert))
         |> push_event("open-modal", %{id: "new-project-modal"})}
    end
  end

  defp assign_project_form(socket, changeset) do
    assign(socket, :project_form, to_form(interpolate_errors(changeset), as: :project))
  end

  defp interpolate_errors(%Ecto.Changeset{} = changeset) do
    Map.update!(changeset, :errors, fn errors -> Enum.map(errors, &interpolate_error/1) end)
  end

  defp interpolate_error({field, {message, opts}}) do
    interpolated =
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)

    {field, {interpolated, opts}}
  end

  defp list_projects(user), do: user |> Projects.list_visible_projects() |> order_projects()

  defp order_projects(projects), do: Enum.sort_by(projects, &project_order/1)

  defp project_order(%{name: "Atlas"}), do: {0, "Atlas"}
  defp project_order(%{name: "Hive"}), do: {1, "Hive"}
  defp project_order(%{name: "Tuist"}), do: {2, "Tuist"}
  defp project_order(%{name: "Kura"}), do: {3, "Kura"}
  defp project_order(%{name: "Noora"}), do: {4, "Noora"}
  defp project_order(%{name: "Once"}), do: {5, "Once"}
  defp project_order(project), do: {6, String.downcase(project.name)}

  attr :form, :any, required: true

  defp new_project_modal(assigns) do
    ~H"""
    <.modal
      id="new-project-modal"
      title="New project"
      description="Create a product, codebase, or service that can own domains and sources."
      header_type="icon"
      header_size="large"
      on_dismiss="cancel_new_project"
    >
      <:trigger :let={attrs}>
        <.button label="Add project" size="medium" variant="primary" {attrs}>
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="apps" />
      </:header_icon>

      <.form
        id="new-project-form"
        for={@form}
        phx-change="validate"
        phx-submit="create"
        data-part="form"
      >
        <.text_input
          id="new-project-name"
          field={@form[:name]}
          label="Name"
          placeholder="Noora"
          required={true}
          show_required={true}
        />
        <.text_area
          id="new-project-description"
          field={@form[:description]}
          label="Description"
          placeholder="What this project covers."
          max_length={500}
          rows={4}
        />
        <div data-part="select-field">
          <span>Visibility</span>
          <.select
            id="new-project-visibility"
            name={@form[:visibility].name}
            value={Phoenix.HTML.Form.normalize_value("select", @form[:visibility].value)}
            label="Choose visibility"
          >
            <:item value="public" label="Public" icon="world" />
            <:item value="private" label="Private" icon="lock" />
          </.select>
        </div>
      </.form>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label="Cancel"
              variant="secondary"
              size="medium"
              type="button"
              phx-click="cancel_new_project"
            />
          </:action>
          <:action>
            <.button
              label="Create project"
              size="medium"
              variant="primary"
              type="submit"
              form="new-project-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end
end

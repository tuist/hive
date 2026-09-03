defmodule HiveWeb.ProjectLive.Show do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  alias Hive.Auth
  alias Hive.Errors
  alias Hive.Errors.ProjectKey
  alias Hive.GitHub.Repositories, as: RepositoryOption
  alias Hive.Projects
  alias Hive.Projects.Webhook
  alias Hive.Projects.Webhooks
  alias HiveWeb.Endpoint
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias Phoenix.LiveView.JS

  def open_graph(project) do
    %{
      description:
        project.description ||
          dgettext(
            "dashboard_projects",
            "Repositories, domains, and drop sources tracked under the %{project} project.",
            project: project.name
          ),
      section_label: dgettext("dashboard_projects", "Project"),
      highlights: [
        project.name,
        dgettext("dashboard_projects", "%{count} domains", count: length(project.domains)),
        dgettext("dashboard_projects", "%{count} repositories",
          count: length(project.github_repositories)
        )
      ],
      id: "project-#{project.id}",
      path: "/projects/#{project.id}",
      title: project.name
    }
  end

  def slack_unfurl(uri, %{"id" => id}) do
    case Projects.fetch_visible_project(id, nil) do
      {:ok, project} -> Hive.Slack.Unfurl.BlockKit.open_graph(uri, open_graph(project))
      {:error, :not_found} -> :skip
    end
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns[:current_user]
    editable? = Auth.member?(user)

    case Projects.fetch_visible_project(id, user) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(
           :page_title,
           dgettext("dashboard_projects", "%{project} · Projects · %{product}",
             project: project.name,
             product: socket.assigns.product_name
           )
         )
         |> assign(:editable?, editable?)
         |> assign(:atom_feed, %{
           title:
             dgettext("dashboard_projects", "Hive · %{project} drops", project: project.name),
           atom_href: "/projects/#{project.id}/drops/atom.xml",
           rss_href: "/projects/#{project.id}/drops/rss.xml"
         })
         |> assign(:project, project)
         |> assign_resource_forms(project)
         |> assign_webhook_resources(project, editable?)
         |> assign_project_form(Projects.change_project(project))
         |> assign(:delete_project_form, delete_project_form())
         |> assign(:errors_enabled?, Errors.enabled?())
         |> assign(:project_key, Errors.primary_project_key(project))
         |> assign(OpenGraph.assigns(open_graph(project)))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_projects", "Project not found."))
         |> redirect(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_project_form(socket, changeset)}
  end

  def handle_event("save", %{"project" => params}, socket) do
    if socket.assigns.editable? do
      update_project(socket, params)
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_projects", "Only organization members can edit projects.")
       )}
    end
  end

  def handle_event("select_link_repository", %{"owner" => owner, "name" => name} = params, socket) do
    repository = %RepositoryOption{
      owner: owner,
      name: name,
      description: Map.get(params, "description")
    }

    {:noreply, assign(socket, :selected_repository, repository)}
  end

  def handle_event("link_repository", %{"repository" => params}, socket) do
    if socket.assigns.editable? do
      link_repository(socket, params)
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_projects", "Only organization members can link repositories.")
       )}
    end
  end

  def handle_event("close_link_repository", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_repository, nil)
     |> assign_repository_form(Projects.change_repository_for_project(socket.assigns.project))
     |> push_event("close-modal", %{id: "link-repository-modal"})}
  end

  def handle_event("link_repository_modal_open_change", %{"open" => true}, socket) do
    {:noreply, ensure_repositories_loaded(socket)}
  end

  def handle_event("link_repository_modal_open_change", %{"open" => false}, socket) do
    {:noreply,
     socket
     |> assign(:selected_repository, nil)
     |> assign_repository_form(Projects.change_repository_for_project(socket.assigns.project))}
  end

  def handle_event("link_repository_modal_open_change", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("link_domain", %{"link_domain" => %{"domain_id" => domain_id}}, socket) do
    if socket.assigns.editable? do
      link_domain(socket, domain_id)
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_projects", "Only organization members can link domains.")
       )}
    end
  end

  def handle_event("close_link_domain", _params, socket) do
    {:noreply,
     socket
     |> assign_link_domain_form(socket.assigns.available_domains)
     |> push_event("close-modal", %{id: "link-domain-modal"})}
  end

  def handle_event("close_delete_project", _params, socket) do
    {:noreply,
     socket
     |> assign(:delete_project_form, delete_project_form())
     |> push_event("close-modal", %{id: "delete-project-modal"})}
  end

  def handle_event("create_webhook", %{"webhook" => params}, socket) do
    if socket.assigns.editable? do
      do_create_webhook(socket, params)
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_projects", "Only organization members can manage webhooks.")
       )}
    end
  end

  def handle_event("select_webhook_source", %{"source" => source}, socket) do
    case parse_webhook_source(source) do
      {:ok, source} -> {:noreply, assign(socket, :selected_source, source)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("close_new_webhook", _params, socket) do
    {:noreply,
     socket
     |> assign(:webhook_form, webhook_form())
     |> assign(:selected_source, default_webhook_source())
     |> push_event("close-modal", %{id: "new-webhook-modal"})}
  end

  def handle_event("new_webhook_modal_open_change", %{"open" => false}, socket) do
    {:noreply,
     socket
     |> assign(:webhook_form, webhook_form())
     |> assign(:selected_source, default_webhook_source())}
  end

  def handle_event("new_webhook_modal_open_change", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("dismiss_created_webhook", _params, socket) do
    {:noreply, assign(socket, :created_webhook_url, nil)}
  end

  def handle_event("delete_webhook", %{"id" => id}, socket) do
    if socket.assigns.editable? do
      do_delete_webhook(socket, id)
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_projects", "Only organization members can manage webhooks.")
       )}
    end
  end

  def handle_event("delete_project", %{"name" => name}, socket) do
    cond do
      not socket.assigns.editable? ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_projects", "Only organization members can delete projects.")
         )}

      name == socket.assigns.project.name ->
        {:ok, _project} = Projects.delete_project(socket.assigns.project)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_projects", "Project deleted."))
         |> push_event("close-modal", %{id: "delete-project-modal"})
         |> push_navigate(to: ~p"/projects")}

      true ->
        {:noreply, assign(socket, :delete_project_form, delete_project_form())}
    end
  end

  def handle_event("remove_repository", %{"id" => repository_id}, socket) do
    if socket.assigns.editable? do
      remove_repository(socket, repository_id)
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_projects", "Only organization members can remove repositories.")
       )}
    end
  end

  def handle_event("remove_domain", %{"id" => domain_id}, socket) do
    if socket.assigns.editable? do
      :ok = Projects.unlink_domain_from_project(socket.assigns.project, domain_id)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("dashboard_projects", "Domain removed from project."))
       |> reload_project()}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_projects", "Only organization members can remove domains.")
       )}
    end
  end

  def handle_event("rotate_error_key", _params, socket) do
    if socket.assigns[:admin?] do
      case Errors.rotate_project_key(socket.assigns.project) do
        {:ok, key} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             dgettext(
               "dashboard_projects",
               "Rotated. Update your Sentry-compatible client to the new Data Source Name."
             )
           )
           |> assign(:project_key, key)}

        {:error, _} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("dashboard_projects", "Could not rotate the Data Source Name.")
           )}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_projects", "Only administrators can rotate Data Source Names.")
       )}
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
      member?={@member?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
    >
      <section id="project-show">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{@project.name}</h1>
            <p :if={@project.description}>{@project.description}</p>
          </div>
          <div data-part="header-actions">
            <Layouts.feeds_dropdown
              id={"project-#{@project.id}-feeds-dropdown"}
              atom_href={"/projects/#{@project.id}/drops/atom.xml"}
              rss_href={"/projects/#{@project.id}/drops/rss.xml"}
            />
          </div>
        </div>

        <.card :if={@editable?} title={dgettext("dashboard_projects", "Settings")} icon="apps">
          <.card_section>
            <.form
              id="edit-project-form"
              for={@project_form}
              phx-change="validate"
              phx-submit="save"
              data-part="form"
            >
              <.text_input
                id="project-name"
                field={@project_form[:name]}
                label={dgettext("dashboard_projects", "Name")}
                required={true}
                show_required={true}
              />
              <.text_area
                id="project-description"
                field={@project_form[:description]}
                label={dgettext("dashboard_projects", "Description")}
                max_length={500}
                rows={4}
              />
              <div data-part="select-field">
                <span>{dgettext("dashboard_projects", "Visibility")}</span>
                <.select
                  id="project-visibility"
                  name={@project_form[:visibility].name}
                  value={to_string(@project_form[:visibility].value)}
                  label={dgettext("dashboard_projects", "Choose visibility")}
                >
                  <:item value="public" label={dgettext("dashboard_projects", "Public")} icon="world" />
                  <:item value="private" label={dgettext("dashboard_projects", "Private")} icon="lock" />
                </.select>
              </div>
              <div data-part="form-actions">
                <.button
                  label={dgettext("dashboard_projects", "Save project")}
                  size="medium"
                  variant="primary"
                />
              </div>
            </.form>
          </.card_section>
        </.card>

        <.card
          :if={@errors_enabled? and @admin? and @project_key}
          title={dgettext("dashboard_projects", "Error tracking")}
          icon="alert_hexagon"
        >
          <.card_section data-part="error-tracking-card">
            <p data-part="error-tracking-intro">
              {dgettext(
                "dashboard_projects",
                "Point any Sentry-compatible client at this Data Source Name and its events will show up on the Errors dashboard scoped to this project."
              )}
            </p>

            <div data-part="dsn-row">
              <div data-part="dsn-value">
                <code>{ProjectKey.dsn(@project_key, Endpoint.url())}</code>
                <.button
                  id={"copy-dsn-#{@project_key.id}"}
                  variant="secondary"
                  size="small"
                  icon_only
                  type="button"
                  phx-hook="Clipboard"
                  data-clipboard-value={ProjectKey.dsn(@project_key, Endpoint.url())}
                  aria-label={dgettext("dashboard_projects", "Copy Data Source Name")}
                  data-part="copy-button"
                >
                  <span data-part="copy-icon"><.icon name="copy" /></span>
                  <span data-part="copy-check-icon"><.icon name="copy_check" /></span>
                </.button>
              </div>
              <div data-part="dsn-meta">
                <span :if={@project_key.last_used_at}>
                  {dgettext("dashboard_projects", "Last used %{when}",
                    when: format_short_datetime(@project_key.last_used_at)
                  )}
                </span>
                <span :if={!@project_key.last_used_at}>
                  {dgettext("dashboard_projects", "Never used")}
                </span>
                <.button
                  variant="secondary"
                  size="small"
                  label={dgettext("dashboard_projects", "Rotate")}
                  phx-click="rotate_error_key"
                  data-confirm={
                    dgettext(
                      "dashboard_projects",
                      "Rotating the Data Source Name invalidates the current one. Clients using it will need to be updated with the new value."
                    )
                  }
                />
              </div>
            </div>
          </.card_section>
        </.card>

        <.card title={dgettext("dashboard_projects", "Repositories")} icon="brand_github">
          <:actions :if={@editable?}>
            <.link_repository_modal
              form={@repository_form}
              repository_options={@repository_options}
              repository_load_error={@repository_load_error}
              selected_repository={@selected_repository}
            />
          </:actions>

          <.card_section>
            <div data-part="resource-table">
              <.table
                id="project-repositories-table"
                rows={@project.github_repositories}
                row_key={fn repository -> "repository-#{repository.id}" end}
              >
                <:col :let={repository} label={dgettext("dashboard_projects", "Repository")}>
                  <.text_and_description_cell
                    label={repository_full_name(repository)}
                    description={dgettext("dashboard_projects", "Linked repository")}
                    icon="brand_github"
                  />
                </:col>
                <:col :if={@editable?} :let={repository} label="">
                  <.button_cell>
                    <:button>
                      <.button
                        label={dgettext("dashboard_projects", "Remove repository")}
                        size="large"
                        variant="secondary"
                        icon_only={true}
                        phx-click="remove_repository"
                        phx-value-id={repository.id}
                        data-confirm={
                          dgettext(
                            "dashboard_projects",
                            "Remove %{repository} from this project?",
                            repository: repository_full_name(repository)
                          )
                        }
                        title={dgettext("dashboard_projects", "Remove repository")}
                        aria-label={dgettext("dashboard_projects", "Remove repository")}
                      >
                        <.trash />
                      </.button>
                    </:button>
                  </.button_cell>
                </:col>
                <:empty_state>
                  <.table_empty_state
                    icon="brand_github"
                    title={dgettext("dashboard_projects", "No repositories linked yet")}
                    subtitle={dgettext("dashboard_projects", "Linked repositories appear here.")}
                  />
                </:empty_state>
              </.table>
            </div>
          </.card_section>
        </.card>

        <.card title={dgettext("dashboard_projects", "Domains")} icon="treemap">
          <:actions :if={@editable?}>
            <.link_domain_modal
              form={@link_domain_form}
              available_domains={@available_domains}
            />
          </:actions>

          <.card_section>
            <div data-part="resource-table">
              <.table
                id="project-domains-table"
                rows={@project.domains}
                row_key={fn domain -> "domain-#{domain.id}" end}
              >
                <:col :let={domain} label={dgettext("dashboard_projects", "Domain")}>
                  <div data-part="cell" data-type="text_and_description">
                    <div data-part="column">
                      <.link navigate={~p"/domains/#{domain.id}"} data-part="domain-title-link">
                        <span data-part="label">{domain.name}</span>
                      </.link>
                      <span data-part="description">
                        {domain.description || dgettext("dashboard_projects", "No description yet.")}
                      </span>
                    </div>
                  </div>
                </:col>
                <:col :if={@editable?} :let={domain} label="">
                  <.button_cell>
                    <:button>
                      <.button
                        label={dgettext("dashboard_projects", "Remove domain")}
                        size="large"
                        variant="secondary"
                        icon_only={true}
                        phx-click="remove_domain"
                        phx-value-id={domain.id}
                        data-confirm={
                          dgettext("dashboard_projects", "Remove %{domain} from this project?",
                            domain: domain.name
                          )
                        }
                        title={dgettext("dashboard_projects", "Remove domain")}
                        aria-label={dgettext("dashboard_projects", "Remove domain")}
                      >
                        <.trash />
                      </.button>
                    </:button>
                  </.button_cell>
                </:col>
                <:empty_state>
                  <.table_empty_state
                    icon="treemap"
                    title={dgettext("dashboard_projects", "No domains defined")}
                    subtitle={
                      dgettext(
                        "dashboard_projects",
                        "Drops from this project will appear as Unclassified."
                      )
                    }
                  />
                </:empty_state>
              </.table>
            </div>
          </.card_section>
        </.card>

        <.webhooks_card
          :if={@editable?}
          webhooks={@webhooks}
          webhook_form={@webhook_form}
          webhook_sources={@webhook_sources}
          selected_source={@selected_source}
          created_webhook_url={@created_webhook_url}
        />

        <.delete_project_section
          :if={@editable?}
          project={@project}
          delete_project_form={@delete_project_form}
        />
      </section>
    </Layouts.dashboard>
    """
  end

  attr :form, :any, required: true
  attr :repository_options, :list, required: true
  attr :repository_load_error, :string, default: nil
  attr :selected_repository, :any, default: nil

  defp link_repository_modal(assigns) do
    ~H"""
    <.modal
      id="link-repository-modal"
      title={dgettext("dashboard_projects", "Link repository")}
      description={dgettext("dashboard_projects", "Add a GitHub repository that belongs to this project.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close_link_repository"
      on_open_change="link_repository_modal_open_change"
    >
      <:trigger :let={attrs}>
        <.button
          label={dgettext("dashboard_projects", "Link repository")}
          size="medium"
          variant="secondary"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.brand_github />
      </:header_icon>

      <.form
        id="link-repository-form"
        for={@form}
        phx-submit="link_repository"
        data-part="form"
      >
        <input
          type="hidden"
          name="repository[owner]"
          value={selected_repository_owner(@selected_repository)}
        />
        <input
          type="hidden"
          name="repository[name]"
          value={selected_repository_name(@selected_repository)}
        />

        <div data-part="repository-selector">
          <label data-part="field-label" for="link-repository-search">
            {dgettext("dashboard_projects", "GitHub repository")}
          </label>
          <.dropdown
            id="link-repository-dropdown"
            label={selected_repository_label(@selected_repository)}
            data-part="repository-dropdown"
          >
            <:icon>
              <.brand_github />
            </:icon>
            <:search>
              <input
                id="link-repository-search"
                type="search"
                placeholder={dgettext("dashboard_projects", "Search repositories...")}
                data-part="search-input"
              />
            </:search>
            <.dropdown_item
              :for={repository <- sorted_repository_options(@repository_options)}
              value={RepositoryOption.full_name(repository)}
              label={RepositoryOption.full_name(repository)}
              description={repository.description}
              size="large"
              phx-click="select_link_repository"
              phx-value-owner={repository.owner}
              phx-value-name={repository.name}
              phx-value-description={repository.description}
              data-label={repository_search_value(repository)}
              data-selected={selected_repository?(@selected_repository, repository)}
            >
              <:right_icon :if={selected_repository?(@selected_repository, repository)}>
                <.check />
              </:right_icon>
            </.dropdown_item>
          </.dropdown>

          <div :if={@repository_load_error} data-part="repository-message" data-tone="error">
            {@repository_load_error}
          </div>
          <div
            :if={@repository_load_error == nil and @repository_options == []}
            data-part="repository-message"
          >
            {dgettext("dashboard_projects", "No repositories available.")}
          </div>
        </div>
      </.form>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={dgettext("dashboard_projects", "Cancel")}
              variant="secondary"
              size="medium"
              type="button"
              phx-click="close_link_repository"
            />
          </:action>
          <:action>
            <.button
              label={dgettext("dashboard_projects", "Link repository")}
              size="medium"
              variant="primary"
              type="submit"
              form="link-repository-form"
              disabled={is_nil(@selected_repository)}
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :form, :any, required: true
  attr :available_domains, :list, required: true

  defp link_domain_modal(assigns) do
    ~H"""
    <.modal
      id="link-domain-modal"
      title={dgettext("dashboard_projects", "Link domain")}
      description={dgettext("dashboard_projects", "Attach an existing reusable domain to this project.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close_link_domain"
    >
      <:trigger :let={attrs}>
        <.button
          label={dgettext("dashboard_projects", "Link domain")}
          size="medium"
          variant="secondary"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="treemap" />
      </:header_icon>

      <.form id="link-domain-form" for={@form} phx-submit="link_domain" data-part="form">
        <div :if={@available_domains == []} data-part="empty-link-options">
          <p>
            {dgettext("dashboard_projects", "Every existing domain is already linked to this project.")}
          </p>
        </div>

        <div :if={@available_domains != []} data-part="select-field">
          <span>{dgettext("dashboard_projects", "Domain")}</span>
          <.select
            id="link-project-domain"
            name={@form[:domain_id].name}
            value={Phoenix.HTML.Form.normalize_value("select", @form[:domain_id].value)}
            label={dgettext("dashboard_projects", "Choose domain")}
          >
            <:item :for={domain <- @available_domains} value={domain.id} label={domain.name} />
          </.select>
        </div>
      </.form>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={dgettext("dashboard_projects", "Cancel")}
              variant="secondary"
              size="medium"
              type="button"
              phx-click="close_link_domain"
            />
          </:action>
          <:action :if={@available_domains != []}>
            <.button
              label={dgettext("dashboard_projects", "Link domain")}
              size="medium"
              variant="primary"
              type="submit"
              form="link-domain-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :webhooks, :list, required: true
  attr :webhook_form, :any, required: true
  attr :webhook_sources, :list, required: true
  attr :selected_source, :atom, required: true
  attr :created_webhook_url, :string, default: nil

  defp webhooks_card(assigns) do
    ~H"""
    <.card title={dgettext("dashboard_projects", "Webhooks")} icon="webhook">
      <:actions>
        <.new_webhook_modal
          webhook_form={@webhook_form}
          webhook_sources={@webhook_sources}
          selected_source={@selected_source}
        />
      </:actions>

      <.card_section data-part="webhooks-card">
        <.alert
          :if={@created_webhook_url}
          status="success"
          size="large"
          title={dgettext("dashboard_projects", "Webhook URL")}
          data-part="created-webhook"
        >
          <p>{dgettext("dashboard_projects", "Copy this now. It is shown only once.")}</p>
          <code data-part="created-webhook-url">{@created_webhook_url}</code>
          <:action>
            <.button
              label={dgettext("dashboard_projects", "Dismiss")}
              size="small"
              variant="secondary"
              phx-click="dismiss_created_webhook"
            />
          </:action>
        </.alert>

        <div data-part="resource-table">
          <.table
            id="project-webhooks-table"
            rows={@webhooks}
            row_key={fn webhook -> "webhook-#{webhook.id}" end}
          >
            <:col :let={webhook} label={dgettext("dashboard_projects", "Name")}>
              <.text_and_description_cell
                label={webhook.name}
                description={
                  dgettext("dashboard_projects", "Created %{date}",
                    date: format_short_datetime(webhook.inserted_at)
                  )
                }
              />
            </:col>
            <:col :let={webhook} label={dgettext("dashboard_projects", "Source")}>
              <div data-part="cell" data-type="badge">
                <.badge
                  label={Webhook.source_label(webhook.source)}
                  color="information"
                  style="light-fill"
                  size="large"
                >
                  <:icon><.bell /></:icon>
                </.badge>
              </div>
            </:col>
            <:col :let={webhook} label={dgettext("dashboard_projects", "Last used")}>
              <.text_cell label={last_used_label(webhook.last_used_at)} />
            </:col>
            <:col :let={webhook} label="">
              <.button_cell>
                <:button>
                  <.button
                    label={dgettext("dashboard_projects", "Delete webhook")}
                    size="large"
                    variant="secondary"
                    icon_only={true}
                    phx-click="delete_webhook"
                    phx-value-id={webhook.id}
                    data-confirm={
                      dgettext(
                        "dashboard_projects",
                        "Delete this webhook? The URL will stop working immediately."
                      )
                    }
                    title={dgettext("dashboard_projects", "Delete webhook")}
                    aria-label={dgettext("dashboard_projects", "Delete webhook")}
                  >
                    <.trash />
                  </.button>
                </:button>
              </.button_cell>
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="webhook"
                title={dgettext("dashboard_projects", "No webhooks yet")}
                subtitle={
                  dgettext("dashboard_projects", "Generate a webhook to ingest alerts for this project.")
                }
              />
            </:empty_state>
          </.table>
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :webhook_form, :any, required: true
  attr :webhook_sources, :list, required: true
  attr :selected_source, :atom, required: true

  defp new_webhook_modal(assigns) do
    ~H"""
    <.modal
      id="new-webhook-modal"
      title={dgettext("dashboard_projects", "New webhook")}
      description={
        dgettext("dashboard_projects", "Generate a URL an external source can post alerts to.")
      }
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_webhook"
      on_open_change="new_webhook_modal_open_change"
    >
      <:trigger :let={attrs}>
        <.button
          label={dgettext("dashboard_projects", "New webhook")}
          size="medium"
          variant="secondary"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.bell />
      </:header_icon>
      <.form
        id="new-webhook-form"
        for={@webhook_form}
        phx-submit="create_webhook"
        data-part="form"
      >
        <.text_input
          field={@webhook_form[:name]}
          label={dgettext("dashboard_projects", "Name")}
          placeholder="Grafana production"
          required={true}
          show_required={true}
        />

        <div data-part="select-field">
          <span>{dgettext("dashboard_projects", "Source")}</span>
          <.select
            id="webhook-source"
            name={@webhook_form[:source].name}
            value={Atom.to_string(@selected_source)}
            label={Webhook.source_label(@selected_source)}
          >
            <:item
              :for={source <- @webhook_sources}
              value={Atom.to_string(source)}
              label={Webhook.source_label(source)}
              icon="bell"
            />
          </.select>
        </div>
      </.form>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={dgettext("dashboard_projects", "Cancel")}
              variant="secondary"
              size="medium"
              type="button"
              phx-click="close_new_webhook"
            />
          </:action>
          <:action>
            <.button
              label={dgettext("dashboard_projects", "Generate webhook")}
              size="medium"
              variant="primary"
              type="button"
              phx-click={JS.dispatch("submit", to: "#new-webhook-form")}
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :project, :map, required: true
  attr :delete_project_form, :any, required: true

  defp delete_project_section(assigns) do
    ~H"""
    <.card_section data-part="delete-project-card-section">
      <div data-part="header">
        <span data-part="title">{dgettext("dashboard_projects", "Delete project")}</span>
        <span data-part="subtitle">
          {dgettext("dashboard_projects", "This action cannot be undone.")}
        </span>
      </div>
      <div data-part="content">
        <.form
          data-part="form"
          for={@delete_project_form}
          id="delete-project-form"
          phx-submit="delete_project"
        >
          <.modal
            id="delete-project-modal"
            title={dgettext("dashboard_projects", "Are you sure you want to delete this?")}
            header_size="large"
            on_dismiss="close_delete_project"
          >
            <:trigger :let={attrs}>
              <.button
                label={dgettext("dashboard_projects", "Delete project")}
                variant="destructive"
                size="medium"
                {attrs}
              />
            </:trigger>
            <.line_divider />
            <.alert
              status="warning"
              type="secondary"
              size="small"
              title={
                dgettext(
                  "dashboard_projects",
                  "Deleting the project will permanently remove its project links and sources"
                )
              }
            />
            <.text_input
              label={dgettext("dashboard_projects", "Enter this project's name to confirm")}
              field={@delete_project_form[:name]}
              type="basic"
              placeholder={@project.name}
            />
            <.line_divider />
            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    type="reset"
                    label={dgettext("dashboard_projects", "Cancel")}
                    variant="secondary"
                    size="medium"
                    phx-click="close_delete_project"
                  />
                </:action>
                <:action>
                  <.button
                    type="submit"
                    form="delete-project-form"
                    label={dgettext("dashboard_projects", "Delete")}
                    variant="destructive"
                    size="medium"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </.form>
      </div>
    </.card_section>
    """
  end

  defp do_create_webhook(socket, params) do
    case Webhooks.create(socket.assigns.project, params) do
      {:ok, {webhook, token}} ->
        url = webhook_ingest_url(socket.assigns.project.id, webhook.source, token)

        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext("dashboard_projects", "Webhook created. Copy the URL. It is shown only once.")
         )
         |> assign(:webhooks, Webhooks.list_for_project(socket.assigns.project))
         |> assign(:webhook_form, webhook_form())
         |> assign(:selected_source, default_webhook_source())
         |> assign(:created_webhook_url, url)
         |> push_event("close-modal", %{id: "new-webhook-modal"})}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, dgettext("dashboard_projects", "Couldn't create the webhook."))}
    end
  end

  defp do_delete_webhook(socket, id) do
    case Enum.find(socket.assigns.webhooks, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      webhook ->
        {:ok, _} = Webhooks.delete(webhook)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_projects", "Webhook deleted."))
         |> assign(:webhooks, Webhooks.list_for_project(socket.assigns.project))}
    end
  end

  defp update_project(socket, params) do
    case Projects.update_project(socket.assigns.project, params) do
      {:ok, project} ->
        project = Projects.get_project!(project.id)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_projects", "Project updated."))
         |> assign(
           :page_title,
           dgettext("dashboard_projects", "%{project} · Projects · %{product}",
             project: project.name,
             product: socket.assigns.product_name
           )
         )
         |> assign(:atom_feed, %{
           title:
             dgettext("dashboard_projects", "Hive · %{project} drops", project: project.name),
           atom_href: "/projects/#{project.id}/drops/atom.xml",
           rss_href: "/projects/#{project.id}/drops/rss.xml"
         })
         |> assign(:project, project)
         |> assign_resource_forms(project)
         |> assign_webhook_resources(project, socket.assigns.editable?)
         |> assign_project_form(Projects.change_project(project))
         |> assign(OpenGraph.assigns(open_graph(project)))}

      {:error, changeset} ->
        {:noreply, assign_project_form(socket, Map.put(changeset, :action, :update))}
    end
  end

  defp assign_project_form(socket, changeset),
    do: assign(socket, :project_form, to_form(changeset, as: :project))

  defp ensure_repositories_loaded(%{assigns: %{repository_options_loaded?: true}} = socket),
    do: socket

  defp ensure_repositories_loaded(socket) do
    {repository_options, repository_load_error} =
      case RepositoryOption.list_accessible_repositories() do
        {:ok, repositories} -> {available_repository_options(repositories), nil}
        {:error, reason} -> {[], repository_load_error(reason)}
      end

    socket
    |> assign(:repository_options, repository_options)
    |> assign(:repository_load_error, repository_load_error)
    |> assign(:repository_options_loaded?, true)
  end

  defp repository_load_error({:not_configured, _missing}) do
    dgettext("dashboard_projects", "GitHub App is not configured.")
  end

  defp repository_load_error({:unexpected_status, status, _body}) do
    dgettext("dashboard_projects", "GitHub returned %{status} while loading repositories.",
      status: status
    )
  end

  defp repository_load_error(:invalid_private_key),
    do: dgettext("dashboard_projects", "GitHub App private key is invalid.")

  defp repository_load_error(_reason),
    do: dgettext("dashboard_projects", "GitHub repositories could not be loaded.")

  defp available_repository_options(repositories) do
    linked_repositories = Projects.list_linked_repository_full_names()

    Enum.reject(repositories, fn repository ->
      MapSet.member?(linked_repositories, {repository.owner, repository.name})
    end)
  end

  defp assign_resource_forms(socket, project) do
    available_domains = Projects.list_domains_available_for_project(project)

    socket
    |> assign(:available_domains, available_domains)
    |> assign(:repository_options, [])
    |> assign(:repository_load_error, nil)
    |> assign(:repository_options_loaded?, false)
    |> assign(:selected_repository, nil)
    |> assign_repository_form(Projects.change_repository_for_project(project))
    |> assign_link_domain_form(available_domains)
  end

  defp assign_repository_form(socket, changeset),
    do: assign(socket, :repository_form, to_form(changeset, as: :repository))

  defp assign_webhook_resources(socket, project, editable?) do
    socket
    |> assign(:webhook_sources, Webhook.sources())
    |> assign(:webhook_form, webhook_form())
    |> assign(:selected_source, default_webhook_source())
    |> assign(:created_webhook_url, nil)
    |> assign(:webhooks, if(editable?, do: Webhooks.list_for_project(project), else: []))
  end

  defp assign_link_domain_form(socket, available_domains) do
    assign(socket, :link_domain_form, link_domain_form(available_domains))
  end

  defp delete_project_form, do: to_form(%{"name" => ""})

  defp webhook_form do
    to_form(%{"name" => "", "source" => Atom.to_string(default_webhook_source())}, as: :webhook)
  end

  defp default_webhook_source, do: List.first(Webhook.sources())

  defp parse_webhook_source(value) do
    case Enum.find(Webhook.sources(), &(Atom.to_string(&1) == value)) do
      nil -> :error
      source -> {:ok, source}
    end
  end

  defp webhook_ingest_url(project_id, source, token) do
    Endpoint.url() <> "/webhooks/projects/#{project_id}/#{source}/#{token}"
  end

  defp last_used_label(nil), do: dgettext("dashboard_projects", "never used")

  defp last_used_label(%DateTime{} = at),
    do: dgettext("dashboard_projects", "last used %{date}", date: format_short_datetime(at))

  defp format_short_datetime(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  defp link_domain_form([domain | _domains]),
    do: to_form(%{"domain_id" => domain.id}, as: :link_domain)

  defp link_domain_form([]), do: to_form(%{"domain_id" => ""}, as: :link_domain)

  defp link_repository(socket, params) do
    case Projects.create_repository_for_project(socket.assigns.project, params) do
      {:ok, _repository} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_projects", "Repository linked."))
         |> reload_project()
         |> push_event("close-modal", %{id: "link-repository-modal"})}

      {:error, changeset} ->
        {:noreply, assign_repository_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp link_domain(socket, domain_id) do
    case Projects.link_domain_to_project(socket.assigns.project, domain_id) do
      {:ok, _domain} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_projects", "Domain linked."))
         |> reload_project()
         |> push_event("close-modal", %{id: "link-domain-modal"})}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_projects", "Domain not found."))}
    end
  end

  defp remove_repository(socket, repository_id) do
    case Projects.delete_repository_from_project(socket.assigns.project, repository_id) do
      {:ok, _repository} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_projects", "Repository removed from project."))
         |> reload_project()}

      {:error, :not_found} ->
        {:noreply,
         put_flash(socket, :error, dgettext("dashboard_projects", "Repository not found."))}
    end
  end

  defp reload_project(socket) do
    project = Projects.get_project!(socket.assigns.project.id)

    socket
    |> assign(:project, project)
    |> assign_resource_forms(project)
    |> assign(
      :webhooks,
      if(socket.assigns.editable?, do: Webhooks.list_for_project(project), else: [])
    )
    |> assign(OpenGraph.assigns(open_graph(project)))
  end

  defp repository_full_name(repository), do: "#{repository.owner}/#{repository.name}"

  defp selected_repository_label(nil), do: dgettext("dashboard_projects", "Choose a repository")
  defp selected_repository_label(repository), do: RepositoryOption.full_name(repository)

  defp sorted_repository_options(repositories) do
    Enum.sort_by(repositories, fn repository ->
      repository
      |> RepositoryOption.full_name()
      |> String.downcase()
    end)
  end

  defp repository_search_value(repository) do
    [RepositoryOption.full_name(repository), repository.description]
    |> Enum.filter(&present?/1)
    |> Enum.join(" ")
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp selected_repository?(nil, _repository), do: false

  defp selected_repository?(selected_repository, repository) do
    selected_repository.owner == repository.owner and selected_repository.name == repository.name
  end

  defp selected_repository_owner(nil), do: nil
  defp selected_repository_owner(repository), do: repository.owner

  defp selected_repository_name(nil), do: nil
  defp selected_repository_name(repository), do: repository.name
end

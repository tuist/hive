defmodule HiveWeb.DomainComponents do
  @moduledoc """
  Presentational components for the domains section.
  """

  use HiveWeb, :html

  alias HiveWeb.Layouts

  attr :domains, :list, required: true
  attr :editable?, :boolean, default: false
  attr :form, :any, required: true

  def domains(assigns) do
    ~H"""
    <section id="domains">
      <div data-part="page-header">
        <div data-part="title-group">
          <h1>Domains</h1>
          <p>The domains this Hive instance plans and routes work for.</p>
        </div>
      </div>

      <.card icon="treemap" title="Domains" data-part="domains-card">
        <:actions :if={@editable?}>
          <.new_domain_modal form={@form} />
        </:actions>
        <.card_section data-part="domains-section">
          <div data-part="domains-table">
            <.table
              id="domains-table"
              rows={@domains}
              row_key={fn domain -> "domain-#{domain.id || domain.name}" end}
              row_navigate={
                if @editable?, do: fn domain -> ~p"/domains/#{domain.id}" end, else: nil
              }
            >
              <:col :let={domain} label="Domain">
                <.text_and_description_cell
                  label={domain.name}
                  description={domain_description(domain)}
                />
              </:col>
              <:col :let={domain} label="Projects">
                <div data-part="cell" data-type="badge">
                  <div data-part="project-cell">
                    <.badge
                      :if={domain_projects(domain) == []}
                      label="No project"
                      color="neutral"
                      style="light-fill"
                      size="large"
                    />
                    <.badge
                      :for={project <- domain_projects(domain)}
                      label={project.name}
                      color="neutral"
                      style="light-fill"
                      size="large"
                    >
                      <:icon><.package /></:icon>
                    </.badge>
                  </div>
                </div>
              </:col>
              <:col :let={domain} label="Feed">
                <div :if={domain.id} data-part="cell" data-type="feed">
                  <a
                    href={"/domains/#{domain.id}/atom.xml"}
                    data-part="feed-link"
                    title="Subscribe via Atom"
                  >
                    <.icon name="rss" /><span>Atom</span>
                  </a>
                  <a
                    href={"/domains/#{domain.id}/rss.xml"}
                    data-part="feed-link"
                    title="Subscribe via RSS"
                  >
                    <.icon name="rss" /><span>RSS</span>
                  </a>
                </div>
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="treemap"
                  title="No domains yet"
                  subtitle={domain_empty_subtitle(@editable?)}
                />
              </:empty_state>
            </.table>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :domain, :map, required: true
  attr :editable?, :boolean, default: false
  attr :form, :any, required: true
  attr :delete_domain_form, :any, default: nil

  def domain_detail(assigns) do
    ~H"""
    <section id="domains">
      <div data-part="page-header">
        <div data-part="title-group">
          <h1>{@domain.name}</h1>
          <p>{domain_description(@domain)}</p>
        </div>
        <div data-part="header-actions">
          <Layouts.feeds_dropdown
            id={"domain-#{@domain.id}-feeds-dropdown"}
            atom_href={"/domains/#{@domain.id}/atom.xml"}
            rss_href={"/domains/#{@domain.id}/rss.xml"}
          />
        </div>
      </div>

      <div data-part="domain-detail-layout">
        <.card icon="treemap" title="Domain">
          <.card_section>
            <.form
              :if={@editable?}
              for={@form}
              id="edit-domain-form"
              phx-change="validate"
              phx-submit="save"
              data-part="form"
            >
              <.text_input
                field={@form[:name]}
                label="Name"
                placeholder="Hive"
                required={true}
                show_required={true}
              />
              <.text_area
                field={@form[:description]}
                label="Description"
                placeholder="What this domain covers inside the organization."
                max_length={500}
                rows={4}
              />

              <div data-part="form-actions">
                <.button label="Save domain" size="medium" variant="primary" />
              </div>
            </.form>
            <.domain_readonly :if={!@editable?} domain={@domain} />
          </.card_section>
        </.card>

        <.delete_domain_section
          :if={@editable?}
          domain={@domain}
          delete_domain_form={@delete_domain_form}
        />
      </div>
    </section>
    """
  end

  attr :domain, :map, required: true
  attr :delete_domain_form, :any, required: true

  defp delete_domain_section(assigns) do
    ~H"""
    <.card_section data-part="delete-domain-card-section">
      <div data-part="header">
        <span data-part="title">Delete domain</span>
        <span data-part="subtitle">This action cannot be undone.</span>
      </div>
      <div data-part="content">
        <.form
          data-part="form"
          for={@delete_domain_form}
          id="delete-domain-form"
          phx-submit="delete_domain"
        >
          <.modal
            id="delete-domain-modal"
            title="Are you sure you want to delete this?"
            header_size="large"
            on_dismiss="close_delete_domain"
          >
            <:trigger :let={attrs}>
              <.button label="Delete domain" variant="destructive" size="medium" {attrs} />
            </:trigger>
            <.line_divider />
            <.alert
              status="warning"
              type="secondary"
              size="small"
              title="Deleting the domain will permanently remove all of its data"
            />
            <.text_input
              label="Enter this domain's name to confirm"
              field={@delete_domain_form[:name]}
              type="basic"
              placeholder={@domain.name}
            />
            <.line_divider />
            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    type="reset"
                    label="Cancel"
                    variant="secondary"
                    size="medium"
                    phx-click="close_delete_domain"
                  />
                </:action>
                <:action>
                  <.button
                    type="submit"
                    form="delete-domain-form"
                    label="Delete"
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

  attr :domain, :map, required: true

  defp domain_readonly(assigns) do
    ~H"""
    <dl data-part="domain-readonly">
      <div data-part="row">
        <dt>Projects</dt>
        <dd>
          <div data-part="project-cell">
            <.badge
              :if={domain_projects(@domain) == []}
              label="No project"
              color="neutral"
              style="light-fill"
              size="large"
            />
            <.badge
              :for={project <- domain_projects(@domain)}
              label={project.name}
              color="neutral"
              style="light-fill"
              size="large"
            >
              <:icon><.package /></:icon>
            </.badge>
          </div>
        </dd>
      </div>
    </dl>
    """
  end

  defp domain_empty_subtitle(true),
    do: "Create the first domain to give Hive a domain boundary."

  defp domain_empty_subtitle(false),
    do: "Organization members will populate this list."

  defp domain_projects(%{projects: %Ecto.Association.NotLoaded{}}), do: []
  defp domain_projects(%{projects: projects}) when is_list(projects), do: projects
  defp domain_projects(_domain), do: []

  attr :form, :any, required: true

  defp new_domain_modal(assigns) do
    ~H"""
    <.modal
      id="new-domain-modal"
      title="New domain"
      description="Create a reusable domain the team can link to projects."
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_domain"
    >
      <:trigger :let={attrs}>
        <.button label="Add domain" size="medium" variant="primary" {attrs}>
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.package />
      </:header_icon>
      <.form id="new-domain-form" for={@form} phx-submit="save" data-part="form">
        <.text_input
          field={@form[:name]}
          label="Name"
          placeholder="Hive"
          required={true}
          show_required={true}
        />
        <.text_area
          field={@form[:description]}
          label="Description"
          placeholder="What this domain covers inside the organization."
          max_length={500}
          rows={4}
        />
      </.form>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label="Cancel"
              variant="secondary"
              size="medium"
              phx-click="close_new_domain"
            />
          </:action>
          <:action>
            <.button
              label="Create domain"
              size="medium"
              variant="primary"
              form="new-domain-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp domain_description(%{description: description}) when description in [nil, ""] do
    "No description"
  end

  defp domain_description(%{description: description}), do: description
end

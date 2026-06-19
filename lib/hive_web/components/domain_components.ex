defmodule HiveWeb.DomainComponents do
  @moduledoc """
  Presentational components for the domains section.
  """

  use HiveWeb, :html

  alias Hive.GitHub.Repositories, as: RepositoryOption
  alias Hive.Domains.GitHubRepository
  alias Hive.Domains.Domain
  alias Hive.Domains.Webhook
  alias HiveWeb.Layouts

  attr :domains, :list, required: true
  attr :editable?, :boolean, default: false
  attr :form, :any, required: true
  attr :repository_options, :list, required: true
  attr :repository_load_error, :string, default: nil
  attr :selected_repository, :any, default: nil

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
          <.new_domain_modal
            form={@form}
            repository_options={@repository_options}
            repository_load_error={@repository_load_error}
            selected_repository={@selected_repository}
          />
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
              <:col :let={domain} label="Visibility">
                <div data-part="cell" data-type="badge">
                  <.badge
                    label={visibility_label(domain.visibility)}
                    color={visibility_color(domain.visibility)}
                    style="light-fill"
                    size="large"
                  >
                    <:icon>
                      <.lock :if={domain.visibility == :private} />
                      <.world :if={domain.visibility != :private} />
                    </:icon>
                  </.badge>
                </div>
              </:col>
              <:col :let={domain} label="Repositories">
                <div data-part="cell" data-type="badge">
                  <div data-part="repository-cell">
                    <.badge
                      :if={domain.project.github_repositories == []}
                      label="No repository"
                      color="neutral"
                      style="light-fill"
                      size="large"
                    />
                    <.badge
                      :for={repository <- domain.project.github_repositories}
                      label={GitHubRepository.full_name(repository)}
                      color="neutral"
                      style="light-fill"
                      size="large"
                    >
                      <:icon><.brand_github /></:icon>
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
  attr :repository_options, :list, required: true
  attr :repository_load_error, :string, default: nil
  attr :selected_repository, :any, default: nil
  attr :webhooks, :list, default: []
  attr :webhook_form, :any, default: nil
  attr :webhook_sources, :list, default: []
  attr :selected_source, :atom, default: :grafana
  attr :created_webhook_url, :string, default: nil
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
              <input
                type="hidden"
                name="domain[github_repository_owner]"
                value={selected_repository_owner(@selected_repository)}
              />
              <input
                type="hidden"
                name="domain[github_repository_name]"
                value={selected_repository_name(@selected_repository)}
              />
              <input
                type="hidden"
                name="domain[github_repository_visibility]"
                value={selected_repository_visibility(@selected_repository)}
              />

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

              <.visibility_select form={@form} id="domain-visibility" />

              <div data-part="repository-selector">
                <label data-part="field-label" for="domain-repository-search">
                  GitHub repository
                </label>
                <.dropdown
                  id="domain-repository-dropdown"
                  label={selected_repository_label(@selected_repository)}
                  data-part="repository-dropdown"
                  on_open_change="repository_dropdown_open_change"
                >
                  <:icon>
                    <.brand_github />
                  </:icon>
                  <:search>
                    <input
                      id="domain-repository-search"
                      type="search"
                      placeholder="Search repositories..."
                      data-part="search-input"
                    />
                  </:search>
                  <.dropdown_item
                    :for={repository <- sorted_repository_options(@repository_options)}
                    value={RepositoryOption.full_name(repository)}
                    label={RepositoryOption.full_name(repository)}
                    description={repository.description}
                    size="large"
                    phx-click="select_repository"
                    phx-value-owner={repository.owner}
                    phx-value-name={repository.name}
                    phx-value-description={repository.description}
                    data-label={repository_search_value(repository)}
                    phx-value-visibility={repository.visibility}
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
              </div>

              <div data-part="form-actions">
                <.button label="Save domain" size="medium" variant="primary" />
              </div>
            </.form>
            <.domain_readonly :if={!@editable?} domain={@domain} />
          </.card_section>
        </.card>

        <.webhooks_card
          :if={@editable?}
          domain={@domain}
          webhooks={@webhooks}
          webhook_form={@webhook_form}
          webhook_sources={@webhook_sources}
          selected_source={@selected_source}
          created_webhook_url={@created_webhook_url}
        />

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
        <dt>Visibility</dt>
        <dd>
          <.badge
            label={visibility_label(@domain.visibility)}
            color={visibility_color(@domain.visibility)}
            style="light-fill"
            size="large"
          >
            <:icon>
              <.lock :if={@domain.visibility == :private} />
              <.world :if={@domain.visibility != :private} />
            </:icon>
          </.badge>
        </dd>
      </div>
      <div data-part="row">
        <dt>Repositories</dt>
        <dd>
          <div data-part="repository-cell">
            <.badge
              :if={@domain.project.github_repositories == []}
              label="No repository"
              color="neutral"
              style="light-fill"
              size="large"
            />
            <.badge
              :for={repository <- @domain.project.github_repositories}
              label={GitHubRepository.full_name(repository)}
              color="neutral"
              style="light-fill"
              size="large"
            >
              <:icon><.brand_github /></:icon>
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

  attr :domain, :map, required: true
  attr :webhooks, :list, required: true
  attr :webhook_form, :any, required: true
  attr :webhook_sources, :list, required: true
  attr :selected_source, :atom, required: true
  attr :created_webhook_url, :string, default: nil

  defp webhooks_card(assigns) do
    ~H"""
    <.card_section data-part="webhooks-card">
      <div data-part="header">
        <div data-part="title-group">
          <span data-part="title">Webhooks</span>
          <span data-part="subtitle">
            Generate a URL that an external source can POST alerts to. The URL carries a
            per-webhook token. Hive only keeps a hash, so the URL is revealed once at
            creation. To rotate, delete a webhook and create a new one.
          </span>
        </div>
        <div data-part="actions">
          <.new_webhook_modal
            webhook_form={@webhook_form}
            webhook_sources={@webhook_sources}
            selected_source={@selected_source}
          />
        </div>
      </div>

      <.alert
        :if={@created_webhook_url}
        status="success"
        size="large"
        title="Webhook URL"
        data-part="created-webhook"
      >
        <p>Copy this now. It is shown only once.</p>
        <code data-part="created-webhook-url">{@created_webhook_url}</code>
        <:action>
          <.button
            label="Dismiss"
            size="small"
            variant="secondary"
            phx-click="dismiss_created_webhook"
          />
        </:action>
      </.alert>

      <.table
        id="domain-webhooks-table"
        rows={@webhooks}
        row_key={fn webhook -> "webhook-#{webhook.id}" end}
      >
        <:col :let={webhook} label="Name">
          <.text_and_description_cell
            label={webhook.name}
            description={"Created " <> format_short_datetime(webhook.inserted_at)}
          />
        </:col>
        <:col :let={webhook} label="Source">
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
        <:col :let={webhook} label="Last used">
          <.text_cell label={last_used_label(webhook.last_used_at)} />
        </:col>
        <:col :let={webhook} label="">
          <.button_cell>
            <:button>
              <.button
                label="Delete webhook"
                size="large"
                variant="secondary"
                icon_only={true}
                phx-click="delete_webhook"
                phx-value-id={webhook.id}
                data-confirm="Delete this webhook? The URL will stop working immediately."
              >
                <.trash />
              </.button>
            </:button>
          </.button_cell>
        </:col>
        <:empty_state>
          <.table_empty_state
            icon="webhook"
            title="No webhooks yet"
            subtitle="Use New webhook to generate one."
          />
        </:empty_state>
      </.table>
    </.card_section>
    """
  end

  attr :webhook_form, :any, required: true
  attr :webhook_sources, :list, required: true
  attr :selected_source, :atom, required: true

  defp new_webhook_modal(assigns) do
    ~H"""
    <.modal
      id="new-webhook-modal"
      title="New webhook"
      description="Generate a URL an external source can POST alerts to."
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_webhook"
      on_open_change="new_webhook_modal_open_change"
    >
      <:trigger :let={attrs}>
        <.button label="New webhook" size="medium" variant="primary" {attrs}>
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
        <input type="hidden" name="webhook[source]" value={Atom.to_string(@selected_source)} />

        <.text_input
          field={@webhook_form[:name]}
          label="Name"
          placeholder="Grafana domainion"
          required={true}
          show_required={true}
        />

        <div data-part="source-selector">
          <label data-part="field-label" for="webhook-source-dropdown">Source</label>
          <.dropdown
            id="webhook-source-dropdown"
            label={Webhook.source_label(@selected_source)}
            data-part="source-dropdown"
          >
            <:icon><.bell /></:icon>
            <.dropdown_item
              :for={source <- @webhook_sources}
              value={Atom.to_string(source)}
              label={Webhook.source_label(source)}
              size="large"
              phx-click="select_webhook_source"
              phx-value-source={Atom.to_string(source)}
              data-selected={@selected_source == source}
            >
              <:left_icon><.bell /></:left_icon>
              <:right_icon :if={@selected_source == source}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
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
              phx-click="close_new_webhook"
            />
          </:action>
          <:action>
            <.button
              label="Generate webhook"
              size="medium"
              variant="primary"
              type="submit"
              form="new-webhook-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp last_used_label(nil), do: "never used"
  defp last_used_label(%DateTime{} = at), do: "last used #{format_short_datetime(at)}"

  defp format_short_datetime(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  defp new_domain_modal(assigns) do
    ~H"""
    <.modal
      id="new-domain-modal"
      title="New domain"
      description="Connect the domain to an optional GitHub repository."
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_domain"
      on_open_change="new_domain_modal_open_change"
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
        <input
          type="hidden"
          name="domain[github_repository_owner]"
          value={selected_repository_owner(@selected_repository)}
        />
        <input
          type="hidden"
          name="domain[github_repository_name]"
          value={selected_repository_name(@selected_repository)}
        />
        <input
          type="hidden"
          name="domain[github_repository_visibility]"
          value={selected_repository_visibility(@selected_repository)}
        />

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

        <.visibility_select form={@form} id="new-domain-visibility" />

        <div data-part="repository-selector">
          <label data-part="field-label" for="repository-search">GitHub repository</label>
          <.dropdown
            id="repository-dropdown"
            label={selected_repository_label(@selected_repository)}
            data-part="repository-dropdown"
          >
            <:icon>
              <.brand_github />
            </:icon>
            <:search>
              <input
                id="repository-search"
                type="search"
                placeholder="Search repositories..."
                data-part="search-input"
              />
            </:search>
            <.dropdown_item
              :for={repository <- sorted_repository_options(@repository_options)}
              value={RepositoryOption.full_name(repository)}
              label={RepositoryOption.full_name(repository)}
              description={repository.description}
              size="large"
              phx-click="select_repository"
              phx-value-owner={repository.owner}
              phx-value-name={repository.name}
              phx-value-description={repository.description}
              data-label={repository_search_value(repository)}
              phx-value-visibility={repository.visibility}
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
        </div>
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

  attr :form, :any, required: true
  attr :id, :string, required: true

  defp visibility_select(assigns) do
    assigns =
      assign(
        assigns,
        :value,
        Phoenix.HTML.Form.normalize_value("select", assigns.form[:visibility].value)
      )

    ~H"""
    <div data-part="select-field">
      <span>Visibility</span>
      <.select id={@id} name={@form[:visibility].name} value={@value} label="Choose visibility">
        <:item
          :for={visibility <- Domain.visibilities()}
          value={Atom.to_string(visibility)}
          label={visibility_label(visibility)}
          icon={visibility_icon(visibility)}
        />
      </.select>
    </div>
    """
  end

  defp visibility_label(:private), do: "Private"
  defp visibility_label(_visibility), do: "Public"

  defp visibility_color(:private), do: "attention"
  defp visibility_color(_visibility), do: "success"

  defp visibility_icon(:private), do: "lock"
  defp visibility_icon(_visibility), do: "world"

  defp selected_repository_label(nil), do: "Choose a repository"
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

  defp selected_repository_visibility(nil), do: nil

  defp selected_repository_visibility(%{visibility: visibility}) when not is_nil(visibility),
    do: Atom.to_string(visibility)

  defp selected_repository_visibility(_repository), do: nil
end

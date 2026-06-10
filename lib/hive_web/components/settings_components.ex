defmodule HiveWeb.SettingsComponents do
  @moduledoc """
  Presentational components for instance settings.
  """

  use HiveWeb, :html

  alias Hive.GitHub.Repositories, as: RepositoryOption
  alias Hive.Products.GitHubRepository
  alias Hive.Products.Product

  attr :products, :list, required: true
  attr :form, :any, required: true
  attr :repository_options, :list, required: true
  attr :repository_load_error, :string, default: nil
  attr :selected_repository, :any, default: nil

  def products(assigns) do
    ~H"""
    <section id="settings">
      <div data-part="page-header">
        <div data-part="title-group">
          <.badge label="Settings" color="information" style="light-fill" />
          <h1>Products</h1>
          <p>Configure the products this Hive instance can plan and route work for.</p>
        </div>
      </div>

      <.card icon="apps" title="Products" data-part="products-card">
        <:actions>
          <.new_product_modal
            form={@form}
            repository_options={@repository_options}
            repository_load_error={@repository_load_error}
            selected_repository={@selected_repository}
          />
        </:actions>
        <.card_section data-part="products-section">
          <div data-part="products-table">
            <.table
              id="products-table"
              rows={@products}
              row_key={fn product -> "product-#{product.id || product.name}" end}
              row_navigate={fn product -> ~p"/settings/products/#{product.id}" end}
            >
              <:col :let={product} label="Product">
                <.text_and_description_cell
                  label={product.name}
                  description={product_description(product)}
                />
              </:col>
              <:col :let={product} label="Visibility">
                <div data-part="cell" data-type="badge">
                  <.badge
                    label={visibility_label(product.visibility)}
                    color={visibility_color(product.visibility)}
                    style="light-fill"
                    size="large"
                  >
                    <:icon>
                      <.lock :if={product.visibility == :private} />
                      <.world :if={product.visibility != :private} />
                    </:icon>
                  </.badge>
                </div>
              </:col>
              <:col :let={product} label="Repositories">
                <div data-part="cell" data-type="badge">
                  <div data-part="repository-cell">
                    <.badge
                      :if={product.github_repositories == []}
                      label="No repository"
                      color="neutral"
                      style="light-fill"
                      size="large"
                    />
                    <.badge
                      :for={repository <- product.github_repositories}
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
              <:empty_state>
                <.table_empty_state
                  icon="package"
                  title="No products configured"
                  subtitle="Create the first product to give Hive a product boundary."
                />
              </:empty_state>
            </.table>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :product, :map, required: true
  attr :form, :any, required: true
  attr :repository_options, :list, required: true
  attr :repository_load_error, :string, default: nil
  attr :selected_repository, :any, default: nil

  def product_detail(assigns) do
    ~H"""
    <section id="settings">
      <div data-part="page-header">
        <div data-part="title-group">
          <.badge label="Settings" color="information" style="light-fill" />
          <h1>{@product.name}</h1>
          <p>{product_description(@product)}</p>
        </div>
      </div>

      <div data-part="product-detail-layout">
        <.card icon="package" title="Product">
          <.card_section>
            <.form for={@form} phx-change="validate" phx-submit="save" data-part="form">
              <input
                type="hidden"
                name="product[github_repository_owner]"
                value={selected_repository_owner(@selected_repository)}
              />
              <input
                type="hidden"
                name="product[github_repository_name]"
                value={selected_repository_name(@selected_repository)}
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
                placeholder="What this product covers inside the organization."
                max_length={500}
                rows={4}
              />

              <.visibility_select form={@form} id="product-visibility" />

              <div data-part="repository-selector">
                <label data-part="field-label" for="product-repository-search">
                  GitHub repository
                </label>
                <.dropdown
                  id="product-repository-dropdown"
                  label={selected_repository_label(@selected_repository)}
                  data-part="repository-dropdown"
                  on_open_change="repository_dropdown_open_change"
                >
                  <:icon>
                    <.brand_github />
                  </:icon>
                  <:search>
                    <input
                      id="product-repository-search"
                      type="search"
                      placeholder="Search repositories..."
                      data-part="search-input"
                    />
                  </:search>
                  <.dropdown_item
                    :for={repository <- @repository_options}
                    value={RepositoryOption.full_name(repository)}
                    label={RepositoryOption.full_name(repository)}
                    description={repository.description}
                    size="large"
                    phx-click="select_repository"
                    phx-value-owner={repository.owner}
                    phx-value-name={repository.name}
                    phx-value-description={repository.description}
                    data-selected={selected_repository?(@selected_repository, repository)}
                  >
                    <:left_icon><.brand_github /></:left_icon>
                    <:right_icon :if={selected_repository?(@selected_repository, repository)}>
                      <.check />
                    </:right_icon>
                  </.dropdown_item>
                </.dropdown>

                <div :if={@selected_repository} data-part="selected-repository">
                  <.badge
                    label={RepositoryOption.full_name(@selected_repository)}
                    color="neutral"
                    style="light-fill"
                  >
                    <:icon><.brand_github /></:icon>
                  </.badge>
                  <.button
                    label="Clear"
                    size="small"
                    variant="secondary"
                    phx-click="clear_repository"
                  />
                </div>

                <div :if={@repository_load_error} data-part="repository-message" data-tone="error">
                  {@repository_load_error}
                </div>
              </div>

              <div data-part="form-actions">
                <.button label="Save product" size="medium" variant="primary" />
              </div>
            </.form>
          </.card_section>
        </.card>
      </div>
    </section>
    """
  end

  defp new_product_modal(assigns) do
    ~H"""
    <.modal
      id="new-product-modal"
      title="New product"
      description="Connect the product to an optional GitHub repository."
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_product"
      on_open_change="new_product_modal_open_change"
    >
      <:trigger :let={attrs}>
        <.button label="Add product" size="medium" variant="primary" {attrs}>
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.package />
      </:header_icon>
      <.form id="new-product-form" for={@form} phx-submit="save" data-part="form">
        <input
          type="hidden"
          name="product[github_repository_owner]"
          value={selected_repository_owner(@selected_repository)}
        />
        <input
          type="hidden"
          name="product[github_repository_name]"
          value={selected_repository_name(@selected_repository)}
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
          placeholder="What this product covers inside the organization."
          max_length={500}
          rows={4}
        />

        <.visibility_select form={@form} id="new-product-visibility" />

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
              :for={repository <- @repository_options}
              value={RepositoryOption.full_name(repository)}
              label={RepositoryOption.full_name(repository)}
              description={repository.description}
              size="large"
              phx-click="select_repository"
              phx-value-owner={repository.owner}
              phx-value-name={repository.name}
              phx-value-description={repository.description}
              data-selected={selected_repository?(@selected_repository, repository)}
            >
              <:left_icon><.brand_github /></:left_icon>
              <:right_icon :if={selected_repository?(@selected_repository, repository)}>
                <.check />
              </:right_icon>
            </.dropdown_item>
          </.dropdown>

          <div :if={@selected_repository} data-part="selected-repository">
            <.badge
              label={RepositoryOption.full_name(@selected_repository)}
              color="neutral"
              style="light-fill"
            >
              <:icon><.brand_github /></:icon>
            </.badge>
            <.button
              label="Clear"
              size="small"
              variant="secondary"
              phx-click="clear_repository"
            />
          </div>

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
              phx-click="close_new_product"
            />
          </:action>
          <:action>
            <.button
              label="Create product"
              size="medium"
              variant="primary"
              form="new-product-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp product_description(%{description: description}) when description in [nil, ""] do
    "No description"
  end

  defp product_description(%{description: description}), do: description

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
          :for={visibility <- Product.visibilities()}
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

  defp selected_repository?(nil, _repository), do: false

  defp selected_repository?(selected_repository, repository) do
    selected_repository.owner == repository.owner and selected_repository.name == repository.name
  end

  defp selected_repository_owner(nil), do: nil
  defp selected_repository_owner(repository), do: repository.owner

  defp selected_repository_name(nil), do: nil
  defp selected_repository_name(repository), do: repository.name
end

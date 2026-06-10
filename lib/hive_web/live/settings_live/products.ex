defmodule HiveWeb.SettingsLive.Products do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias Hive.Products
  alias Hive.Products.Product
  alias HiveWeb.Layouts
  alias HiveWeb.SettingsComponents

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.signed_in? and Auth.member?(socket.assigns.current_user) do
      {:ok,
       socket
       |> assign(:page_title, "Products · #{socket.assigns.product_name}")
       |> assign(:products, Products.list_products())
       |> assign(:repository_options, [])
       |> assign(:repository_load_error, nil)
       |> assign(:repository_options_loaded?, false)
       |> assign(:selected_repository, nil)
       |> assign_form(Products.change_product())}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have access to configure products.")
       |> redirect(to: ~p"/login")}
    end
  end

  @impl true
  def handle_event("close_new_product", _params, socket) do
    {:noreply,
     socket |> reset_new_product() |> push_event("close-modal", %{id: "new-product-modal"})}
  end

  def handle_event("new_product_modal_open_change", %{"open" => true}, socket) do
    {:noreply, ensure_repositories_loaded(socket)}
  end

  def handle_event("new_product_modal_open_change", %{"open" => false}, socket) do
    {:noreply, reset_new_product(socket)}
  end

  def handle_event("new_product_modal_open_change", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("validate", %{"product" => params}, socket) do
    changeset =
      %Product{}
      |> Products.change_product(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("select_repository", %{"owner" => owner, "name" => name} = params, socket) do
    repository = %Repositories{
      owner: owner,
      name: name,
      description: Map.get(params, "description")
    }

    {:noreply, assign(socket, :selected_repository, repository)}
  end

  def handle_event("clear_repository", _params, socket) do
    {:noreply, assign(socket, :selected_repository, nil)}
  end

  def handle_event("save", %{"product" => params}, socket) do
    case Products.create_product(params) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product created.")
         |> assign(:products, Products.list_products())
         |> reset_new_product()
         |> push_event("close-modal", %{id: "new-product-modal"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign_form(Map.put(changeset, :action, :insert))
         |> push_event("open-modal", %{id: "new-product-modal"})}
    end
  end

  defp ensure_repositories_loaded(%{assigns: %{repository_options_loaded?: true}} = socket),
    do: socket

  defp ensure_repositories_loaded(socket) do
    {repository_options, repository_load_error} =
      case Repositories.list_accessible_repositories() do
        {:ok, repositories} -> {repositories, nil}
        {:error, reason} -> {[], repository_load_error(reason)}
      end

    socket
    |> assign(:repository_options, repository_options)
    |> assign(:repository_load_error, repository_load_error)
    |> assign(:repository_options_loaded?, true)
  end

  defp repository_load_error({:not_configured, _missing}) do
    "GitHub App is not configured."
  end

  defp repository_load_error({:unexpected_status, status, _body}) do
    "GitHub returned #{status} while loading repositories."
  end

  defp repository_load_error(:invalid_private_key), do: "GitHub App private key is invalid."
  defp repository_load_error(_reason), do: "GitHub repositories could not be loaded."

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :product))
  end

  defp reset_new_product(socket) do
    socket
    |> assign(:selected_repository, nil)
    |> assign_form(Products.change_product())
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
      settings_enabled?={@settings_enabled?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
    >
      <SettingsComponents.products
        products={@products}
        form={@form}
        repository_options={@repository_options}
        repository_load_error={@repository_load_error}
        selected_repository={@selected_repository}
      />
    </Layouts.dashboard>
    """
  end
end

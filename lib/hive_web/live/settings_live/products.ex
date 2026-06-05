defmodule HiveWeb.SettingsLive.Products do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.GitHub.Repositories
  alias Hive.Products
  alias Hive.Products.Product
  alias HiveWeb.Layouts
  alias HiveWeb.SettingsComponents

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.signed_in? do
      {:ok,
       socket
       |> assign(:page_title, "Products · #{socket.assigns.product_name}")
       |> assign(:products, Products.list_products())
       |> assign(:repository_query, "")
       |> assign(:repository_options, [])
       |> assign(:repository_search_error, nil)
       |> assign(:selected_repository, nil)
       |> assign_form(Products.change_product())}
    else
      {:ok,
       socket
       |> put_flash(:error, "Log in to configure products.")
       |> redirect(to: ~p"/login")}
    end
  end

  @impl true
  def handle_event("close_new_product", _params, socket) do
    {:noreply,
     socket |> reset_new_product() |> push_event("close-modal", %{id: "new-product-modal"})}
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

  def handle_event("search_repositories", params, socket) do
    query = repository_query(params)

    case Repositories.search_accessible_repositories(query) do
      {:ok, repositories} ->
        {:noreply,
         socket
         |> assign(:repository_query, query)
         |> assign(:repository_options, repositories)
         |> assign(:repository_search_error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:repository_query, query)
         |> assign(:repository_options, [])
         |> assign(:repository_search_error, repository_search_error(reason))}
    end
  end

  def handle_event("select_repository", %{"owner" => owner, "name" => name} = params, socket) do
    repository = %Repositories{
      owner: owner,
      name: name,
      description: Map.get(params, "description")
    }

    {:noreply,
     socket
     |> assign(:repository_query, Repositories.full_name(repository))
     |> assign(:selected_repository, repository)
     |> assign(:repository_options, [])
     |> assign(:repository_search_error, nil)}
  end

  def handle_event("clear_repository", _params, socket) do
    {:noreply,
     socket
     |> assign(:repository_query, "")
     |> assign(:selected_repository, nil)
     |> assign(:repository_options, [])
     |> assign(:repository_search_error, nil)}
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

  defp repository_query(%{"value" => value}), do: value
  defp repository_query(%{"repository_query" => value}), do: value
  defp repository_query(_params), do: ""

  defp repository_search_error({:not_configured, _missing}) do
    "GitHub App repository search is not configured."
  end

  defp repository_search_error({:unexpected_status, status, _body}) do
    "GitHub returned #{status} while loading repositories."
  end

  defp repository_search_error(:invalid_private_key), do: "GitHub App private key is invalid."
  defp repository_search_error(_reason), do: "GitHub repositories could not be loaded."

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :product))
  end

  defp reset_new_product(socket) do
    socket
    |> assign(:repository_query, "")
    |> assign(:repository_options, [])
    |> assign(:repository_search_error, nil)
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
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
    >
      <SettingsComponents.products
        products={@products}
        form={@form}
        repository_query={@repository_query}
        repository_options={@repository_options}
        repository_search_error={@repository_search_error}
        selected_repository={@selected_repository}
      />
    </Layouts.dashboard>
    """
  end
end

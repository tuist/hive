defmodule HiveWeb.SettingsLive.Product do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias Hive.Products
  alias Hive.Products.Webhook
  alias Hive.Products.Webhooks
  alias HiveWeb.Endpoint
  alias HiveWeb.Layouts
  alias HiveWeb.SettingsComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if socket.assigns.signed_in? and Auth.member?(socket.assigns.current_user) do
      product = Products.get_product!(id)
      selected_repository = selected_repository(product)

      {:ok,
       socket
       |> assign(:page_title, "#{product.name} · Products · #{socket.assigns.product_name}")
       |> assign(:product, product)
       |> assign(:repository_query, repository_query(selected_repository))
       |> assign(:repository_options, [])
       |> assign(:repository_search_error, nil)
       |> assign(:selected_repository, selected_repository)
       |> assign(:webhook_sources, Webhook.sources())
       |> assign(:webhook_form, webhook_form())
       |> assign(:selected_source, default_webhook_source())
       |> assign(:created_webhook_url, nil)
       |> assign(:webhooks, Webhooks.list_for_product(product))
       |> assign_form(Products.change_product(product))}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have access to configure products.")
       |> redirect(to: ~p"/login")}
    end
  end

  @impl true
  def handle_event("validate", %{"product" => params}, socket) do
    changeset =
      socket.assigns.product
      |> Products.change_product(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("search_repositories", params, socket) do
    query = repository_search_query(params)

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

  def handle_event("create_webhook", %{"webhook" => params}, socket) do
    case Webhooks.create(socket.assigns.product, params) do
      {:ok, {webhook, token}} ->
        url = webhook_ingest_url(socket.assigns.product.id, webhook.source, token)

        {:noreply,
         socket
         |> put_flash(:info, "Webhook created. Copy the URL. It is shown only once.")
         |> assign(:webhooks, Webhooks.list_for_product(socket.assigns.product))
         |> assign(:webhook_form, webhook_form())
         |> assign(:selected_source, default_webhook_source())
         |> assign(:created_webhook_url, url)
         |> push_event("close-modal", %{id: "new-webhook-modal"})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't create the webhook.")}
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
    case Enum.find(socket.assigns.webhooks, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      webhook ->
        {:ok, _} = Webhooks.delete(webhook)

        {:noreply,
         socket
         |> put_flash(:info, "Webhook deleted.")
         |> assign(:webhooks, Webhooks.list_for_product(socket.assigns.product))}
    end
  end

  def handle_event("save", %{"product" => params}, socket) do
    case Products.update_product(socket.assigns.product, params) do
      {:ok, product} ->
        product = Products.get_product!(product.id)
        selected_repository = selected_repository(product)

        {:noreply,
         socket
         |> put_flash(:info, "Product updated.")
         |> assign(:page_title, "#{product.name} · Products · #{socket.assigns.product_name}")
         |> assign(:product, product)
         |> assign(:repository_query, repository_query(selected_repository))
         |> assign(:repository_options, [])
         |> assign(:repository_search_error, nil)
         |> assign(:selected_repository, selected_repository)
         |> assign_form(Products.change_product(product))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :update))}
    end
  end

  defp selected_repository(product) do
    product.github_repositories
    |> List.first()
    |> case do
      nil ->
        nil

      repository ->
        %Repositories{owner: repository.owner, name: repository.name}
    end
  end

  defp repository_query(nil), do: ""
  defp repository_query(repository), do: Repositories.full_name(repository)

  defp repository_search_query(%{"value" => value}), do: value
  defp repository_search_query(%{"repository_query" => value}), do: value
  defp repository_search_query(_params), do: ""

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

  defp webhook_form do
    to_form(%{"name" => "", "source" => "grafana"}, as: :webhook)
  end

  defp default_webhook_source, do: List.first(Webhook.sources())

  defp parse_webhook_source(value) do
    case Enum.find(Webhook.sources(), &(Atom.to_string(&1) == value)) do
      nil -> :error
      source -> {:ok, source}
    end
  end

  defp webhook_ingest_url(product_id, source, token) do
    Endpoint.url() <> "/webhooks/products/#{product_id}/#{source}/#{token}"
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
      <SettingsComponents.product_detail
        product={@product}
        form={@form}
        repository_query={@repository_query}
        repository_options={@repository_options}
        repository_search_error={@repository_search_error}
        selected_repository={@selected_repository}
        webhooks={@webhooks}
        webhook_form={@webhook_form}
        webhook_sources={@webhook_sources}
        selected_source={@selected_source}
        created_webhook_url={@created_webhook_url}
      />
    </Layouts.dashboard>
    """
  end
end

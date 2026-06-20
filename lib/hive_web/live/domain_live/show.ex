defmodule HiveWeb.DomainLive.Show do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias Hive.Domains
  alias Hive.Domains.Webhook
  alias Hive.Domains.Webhooks
  alias HiveWeb.Endpoint
  alias HiveWeb.Layouts
  alias HiveWeb.DomainComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    editable? = Auth.member?(user)

    case Domains.fetch_visible_domain(id, user) do
      {:ok, domain} ->
        selected_repository = selected_repository(domain)

        {:ok,
         socket
         |> assign(:page_title, "#{domain.name} · Domains · #{socket.assigns.product_name}")
         |> assign(:atom_feed, %{
           title: "Hive · #{domain.name}",
           atom_href: "/domains/#{domain.id}/atom.xml",
           rss_href: "/domains/#{domain.id}/rss.xml"
         })
         |> assign(:domain, domain)
         |> assign(:editable?, editable?)
         |> assign(:repository_options, [])
         |> assign(:repository_load_error, nil)
         |> assign(:repository_options_loaded?, false)
         |> assign(:selected_repository, selected_repository)
         |> assign(:webhook_sources, Webhook.sources())
         |> assign(:webhook_form, webhook_form())
         |> assign(:selected_source, default_webhook_source())
         |> assign(:created_webhook_url, nil)
         |> assign(:webhooks, if(editable?, do: Webhooks.list_for_domain(domain), else: []))
         |> assign(:delete_domain_form, delete_domain_form())
         |> assign_form(Domains.change_domain(domain))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Domain not found.")
         |> redirect(to: ~p"/domains")}
    end
  end

  @impl true
  def handle_event("validate", %{"domain" => params}, socket) do
    changeset =
      socket.assigns.domain
      |> Domains.change_domain(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("select_repository", %{"owner" => owner, "name" => name} = params, socket) do
    repository = %Repositories{
      owner: owner,
      name: name,
      description: Map.get(params, "description"),
      visibility: parse_visibility(Map.get(params, "visibility"))
    }

    {:noreply, assign(socket, :selected_repository, repository)}
  end

  def handle_event("clear_repository", _params, socket) do
    {:noreply, assign(socket, :selected_repository, nil)}
  end

  def handle_event("repository_dropdown_open_change", %{"open" => true}, socket) do
    {:noreply, ensure_repositories_loaded(socket)}
  end

  def handle_event("repository_dropdown_open_change", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("create_webhook", %{"webhook" => params}, socket) do
    if socket.assigns.editable? do
      do_create_webhook(socket, params)
    else
      {:noreply, put_flash(socket, :error, "Only organization members can manage webhooks.")}
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
      {:noreply, put_flash(socket, :error, "Only organization members can manage webhooks.")}
    end
  end

  def handle_event("save", %{"domain" => params}, socket) do
    if socket.assigns.editable? do
      update_domain(socket, params)
    else
      {:noreply, put_flash(socket, :error, "Only organization members can edit domains.")}
    end
  end

  def handle_event("close_delete_domain", _params, socket) do
    {:noreply,
     socket
     |> assign(:delete_domain_form, delete_domain_form())
     |> push_event("close-modal", %{id: "delete-domain-modal"})}
  end

  def handle_event("delete_domain", %{"name" => name}, socket) do
    cond do
      not socket.assigns.editable? ->
        {:noreply, put_flash(socket, :error, "Only organization members can delete domains.")}

      name == socket.assigns.domain.name ->
        {:ok, _domain} = Domains.delete_domain(socket.assigns.domain)

        {:noreply,
         socket
         |> put_flash(:info, "Domain deleted.")
         |> push_navigate(to: ~p"/domains")}

      true ->
        {:noreply, assign(socket, :delete_domain_form, delete_domain_form())}
    end
  end

  defp do_create_webhook(socket, params) do
    case Webhooks.create(socket.assigns.domain, params) do
      {:ok, {webhook, token}} ->
        url = webhook_ingest_url(socket.assigns.domain.id, webhook.source, token)

        {:noreply,
         socket
         |> put_flash(:info, "Webhook created. Copy the URL. It is shown only once.")
         |> assign(:webhooks, Webhooks.list_for_domain(socket.assigns.domain))
         |> assign(:webhook_form, webhook_form())
         |> assign(:selected_source, default_webhook_source())
         |> assign(:created_webhook_url, url)
         |> push_event("close-modal", %{id: "new-webhook-modal"})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't create the webhook.")}
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
         |> put_flash(:info, "Webhook deleted.")
         |> assign(:webhooks, Webhooks.list_for_domain(socket.assigns.domain))}
    end
  end

  defp update_domain(socket, params) do
    case Domains.update_domain(socket.assigns.domain, params) do
      {:ok, domain} ->
        domain = Domains.get_domain!(domain.id)
        selected_repository = selected_repository(domain)

        {:noreply,
         socket
         |> put_flash(:info, "Domain updated.")
         |> assign(:page_title, "#{domain.name} · Domains · #{socket.assigns.product_name}")
         |> assign(:domain, domain)
         |> assign(:selected_repository, selected_repository)
         |> assign_form(Domains.change_domain(domain))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :update))}
    end
  end

  defp selected_repository(domain) do
    repositories =
      case domain.project do
        %{github_repositories: repos} when is_list(repos) -> repos
        _ -> []
      end

    repositories
    |> List.first()
    |> case do
      nil ->
        nil

      repository ->
        %Repositories{
          owner: repository.owner,
          name: repository.name,
          visibility: repository.visibility
        }
    end
  end

  defp parse_visibility("public"), do: :public
  defp parse_visibility("private"), do: :private
  defp parse_visibility(value) when is_atom(value), do: value
  defp parse_visibility(_value), do: :public

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
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :domain))
  end

  defp webhook_form do
    to_form(%{"name" => "", "source" => "grafana"}, as: :webhook)
  end

  defp delete_domain_form do
    to_form(%{"name" => ""})
  end

  defp default_webhook_source, do: List.first(Webhook.sources())

  defp parse_webhook_source(value) do
    case Enum.find(Webhook.sources(), &(Atom.to_string(&1) == value)) do
      nil -> :error
      source -> {:ok, source}
    end
  end

  defp webhook_ingest_url(domain_id, source, token) do
    Endpoint.url() <> "/webhooks/domains/#{domain_id}/#{source}/#{token}"
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
      admin?={@admin?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
      specs_have_new_activity?={@specs_have_new_activity?}
    >
      <DomainComponents.domain_detail
        domain={@domain}
        editable?={@editable?}
        form={@form}
        repository_options={@repository_options}
        repository_load_error={@repository_load_error}
        selected_repository={@selected_repository}
        webhooks={@webhooks}
        webhook_form={@webhook_form}
        webhook_sources={@webhook_sources}
        selected_source={@selected_source}
        created_webhook_url={@created_webhook_url}
        delete_domain_form={@delete_domain_form}
      />
    </Layouts.dashboard>
    """
  end
end

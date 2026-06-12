defmodule HiveWeb.MeadowLive.Show do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias Hive.Meadows
  alias Hive.Meadows.Webhook
  alias Hive.Meadows.Webhooks
  alias HiveWeb.Endpoint
  alias HiveWeb.Layouts
  alias HiveWeb.MeadowComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    editable? = Auth.member?(user)

    case Meadows.fetch_visible_meadow(id, user) do
      {:ok, meadow} ->
        selected_repository = selected_repository(meadow)

        {:ok,
         socket
         |> assign(:page_title, "#{meadow.name} · Meadows · #{socket.assigns.product_name}")
         |> assign(:meadow, meadow)
         |> assign(:editable?, editable?)
         |> assign(:repository_options, [])
         |> assign(:repository_load_error, nil)
         |> assign(:repository_options_loaded?, false)
         |> assign(:selected_repository, selected_repository)
         |> assign(:webhook_sources, Webhook.sources())
         |> assign(:webhook_form, webhook_form())
         |> assign(:selected_source, default_webhook_source())
         |> assign(:created_webhook_url, nil)
         |> assign(:webhooks, if(editable?, do: Webhooks.list_for_meadow(meadow), else: []))
         |> assign_form(Meadows.change_meadow(meadow))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Meadow not found.")
         |> redirect(to: ~p"/meadows")}
    end
  end

  @impl true
  def handle_event("validate", %{"meadow" => params}, socket) do
    changeset =
      socket.assigns.meadow
      |> Meadows.change_meadow(params)
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

  def handle_event("save", %{"meadow" => params}, socket) do
    if socket.assigns.editable? do
      update_meadow(socket, params)
    else
      {:noreply, put_flash(socket, :error, "Only organization members can edit meadows.")}
    end
  end

  defp do_create_webhook(socket, params) do
    case Webhooks.create(socket.assigns.meadow, params) do
      {:ok, {webhook, token}} ->
        url = webhook_ingest_url(socket.assigns.meadow.id, webhook.source, token)

        {:noreply,
         socket
         |> put_flash(:info, "Webhook created. Copy the URL. It is shown only once.")
         |> assign(:webhooks, Webhooks.list_for_meadow(socket.assigns.meadow))
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
         |> assign(:webhooks, Webhooks.list_for_meadow(socket.assigns.meadow))}
    end
  end

  defp update_meadow(socket, params) do
    case Meadows.update_meadow(socket.assigns.meadow, params) do
      {:ok, meadow} ->
        meadow = Meadows.get_meadow!(meadow.id)
        selected_repository = selected_repository(meadow)

        {:noreply,
         socket
         |> put_flash(:info, "Meadow updated.")
         |> assign(:page_title, "#{meadow.name} · Meadows · #{socket.assigns.product_name}")
         |> assign(:meadow, meadow)
         |> assign(:selected_repository, selected_repository)
         |> assign_form(Meadows.change_meadow(meadow))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :update))}
    end
  end

  defp selected_repository(meadow) do
    meadow.github_repositories
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
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :meadow))
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

  defp webhook_ingest_url(meadow_id, source, token) do
    Endpoint.url() <> "/webhooks/meadows/#{meadow_id}/#{source}/#{token}"
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
    >
      <MeadowComponents.meadow_detail
        meadow={@meadow}
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
      />
    </Layouts.dashboard>
    """
  end
end

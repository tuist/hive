defmodule HiveWeb.DomainLive.Index do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias Hive.Domains
  alias Hive.Domains.Domain
  alias HiveWeb.Layouts
  alias HiveWeb.DomainComponents

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    editable? = Auth.member?(user)

    {:ok,
     socket
     |> assign(:page_title, "Domains · #{socket.assigns.product_name}")
     |> assign(:domains, Domains.list_visible_domains(user))
     |> assign(:editable?, editable?)
     |> assign(:repository_options, [])
     |> assign(:repository_load_error, nil)
     |> assign(:repository_options_loaded?, false)
     |> assign(:selected_repository, nil)
     |> assign_form(Domains.change_domain())}
  end

  @impl true
  def handle_event("close_new_domain", _params, socket) do
    {:noreply,
     socket
     |> reset_new_domain()
     |> push_event("close-modal", %{id: "new-domain-modal"})
     |> push_event("reset-form", %{id: "new-domain-form"})}
  end

  def handle_event("new_domain_modal_open_change", %{"open" => true}, socket) do
    {:noreply, ensure_repositories_loaded(socket)}
  end

  def handle_event("new_domain_modal_open_change", %{"open" => false}, socket) do
    {:noreply,
     socket
     |> reset_new_domain()
     |> push_event("reset-form", %{id: "new-domain-form"})}
  end

  def handle_event("new_domain_modal_open_change", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("validate", %{"domain" => params}, socket) do
    changeset =
      %Domain{}
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

  def handle_event("save", %{"domain" => params}, socket) do
    if socket.assigns.editable? do
      create_domain(socket, params)
    else
      {:noreply, put_flash(socket, :error, "Only organization members can create domains.")}
    end
  end

  defp create_domain(socket, params) do
    case Domains.create_domain(params) do
      {:ok, _domain} ->
        {:noreply,
         socket
         |> put_flash(:info, "Domain created.")
         |> assign(:domains, Domains.list_visible_domains(socket.assigns.current_user))
         |> reset_new_domain()
         |> push_event("close-modal", %{id: "new-domain-modal"})
         |> push_event("reset-form", %{id: "new-domain-form"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign_form(Map.put(changeset, :action, :insert))
         |> push_event("open-modal", %{id: "new-domain-modal"})}
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

  defp parse_visibility("public"), do: :public
  defp parse_visibility("private"), do: :private
  defp parse_visibility(value) when is_atom(value), do: value
  defp parse_visibility(_value), do: :public

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

  defp reset_new_domain(socket) do
    socket
    |> assign(:selected_repository, nil)
    |> assign_form(Domains.change_domain())
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
      <DomainComponents.domains
        domains={@domains}
        editable?={@editable?}
        form={@form}
        repository_options={@repository_options}
        repository_load_error={@repository_load_error}
        selected_repository={@selected_repository}
      />
    </Layouts.dashboard>
    """
  end
end

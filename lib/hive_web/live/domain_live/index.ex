defmodule HiveWeb.DomainLive.Index do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Auth
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

  def handle_event("validate", %{"domain" => params}, socket) do
    changeset =
      %Domain{}
      |> Domains.change_domain(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
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

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :domain))
  end

  defp reset_new_domain(socket) do
    assign_form(socket, Domains.change_domain())
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
      />
    </Layouts.dashboard>
    """
  end
end

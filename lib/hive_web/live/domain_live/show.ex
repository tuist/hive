defmodule HiveWeb.DomainLive.Show do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Auth
  alias Hive.Domains
  alias HiveWeb.Layouts
  alias HiveWeb.DomainComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    editable? = Auth.member?(user)

    case Domains.fetch_visible_domain(id, user) do
      {:ok, domain} ->
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
         |> push_event("close-modal", %{id: "delete-domain-modal"})
         |> push_navigate(to: ~p"/domains")}

      true ->
        {:noreply, assign(socket, :delete_domain_form, delete_domain_form())}
    end
  end

  defp update_domain(socket, params) do
    case Domains.update_domain(socket.assigns.domain, params) do
      {:ok, domain} ->
        domain = Domains.get_domain!(domain.id)

        {:noreply,
         socket
         |> put_flash(:info, "Domain updated.")
         |> assign(:page_title, "#{domain.name} · Domains · #{socket.assigns.product_name}")
         |> assign(:domain, domain)
         |> assign_form(Domains.change_domain(domain))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :update))}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :domain))
  end

  defp delete_domain_form do
    to_form(%{"name" => ""})
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
      flash={@flash}
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
        delete_domain_form={@delete_domain_form}
      />
    </Layouts.dashboard>
    """
  end
end

defmodule HiveWeb.DomainLive.Show do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Auth
  alias Hive.Domains
  alias Hive.Errors
  alias HiveWeb.DomainComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph(domain) do
    %{
      description:
        domain.description ||
          dgettext(
            "dashboard_domains",
            "Specs, forage items, drops, and projects linked to %{domain}.",
            domain: domain.name
          ),
      section_label: dgettext("dashboard_domains", "Domain"),
      highlights: [
        dgettext("dashboard_domains", "%{count} projects", count: length(domain.projects)),
        dgettext("dashboard_domains", "%{visibility} visibility",
          visibility: domain.visibility |> Atom.to_string() |> String.capitalize()
        )
      ],
      id: "domain-#{domain.id}",
      path: "/domains/#{domain.id}",
      title: domain.name
    }
  end

  def slack_unfurl(uri, %{"id" => id}) do
    case Domains.fetch_visible_domain(id, nil) do
      {:ok, domain} -> Hive.Slack.Unfurl.BlockKit.open_graph(uri, open_graph(domain))
      {:error, :not_found} -> :skip
    end
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    editable? = Auth.member?(user)

    case Domains.fetch_visible_domain(id, user) do
      {:ok, domain} ->
        {:ok,
         socket
         |> assign(
           :page_title,
           dgettext("dashboard_domains", "%{domain} · Domains · %{product}",
             domain: domain.name,
             product: socket.assigns.product_name
           )
         )
         |> assign(:atom_feed, %{
           title: dgettext("dashboard_domains", "Hive · %{domain}", domain: domain.name),
           atom_href: "/domains/#{domain.id}/atom.xml",
           rss_href: "/domains/#{domain.id}/rss.xml"
         })
         |> assign(:domain, domain)
         |> assign(:editable?, editable?)
         |> assign(:delete_domain_form, delete_domain_form())
         |> assign(:errors_enabled?, Errors.enabled?())
         |> assign_domain_keys(domain)
         |> assign(OpenGraph.assigns(open_graph(domain)))
         |> assign_form(Domains.change_domain(domain))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_domains", "Domain not found."))
         |> redirect(to: ~p"/domains")}
    end
  end

  # Load one DSN per linked project so the "Error tracking" card can
  # render Copy + Rotate per pair. Only admins see DSNs today, and
  # `primary_domain_key/2` provisions lazily so the first render mints
  # the credential — no separate "generate" step required.
  defp assign_domain_keys(socket, domain) do
    if socket.assigns[:admin?] and socket.assigns[:errors_enabled?] do
      keys =
        Map.new(domain.projects, fn project ->
          {project.id, Errors.primary_domain_key(project, domain)}
        end)

      assign(socket, :domain_keys, keys)
    else
      assign(socket, :domain_keys, %{})
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
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_domains", "Only organization members can edit domains.")
       )}
    end
  end

  def handle_event("close_delete_domain", _params, socket) do
    {:noreply,
     socket
     |> assign(:delete_domain_form, delete_domain_form())
     |> push_event("close-modal", %{id: "delete-domain-modal"})}
  end

  def handle_event("rotate_domain_error_key", %{"project-id" => project_id}, socket) do
    cond do
      not socket.assigns[:admin?] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_domains", "Only administrators can rotate Data Source Names.")
         )}

      project = Enum.find(socket.assigns.domain.projects, &(&1.id == project_id)) ->
        rotate_domain_key(socket, project)

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_domain", %{"name" => name}, socket) do
    cond do
      not socket.assigns.editable? ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_domains", "Only organization members can delete domains.")
         )}

      name == socket.assigns.domain.name ->
        {:ok, _domain} = Domains.delete_domain(socket.assigns.domain)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_domains", "Domain deleted."))
         |> push_event("close-modal", %{id: "delete-domain-modal"})
         |> push_navigate(to: ~p"/domains")}

      true ->
        {:noreply, assign(socket, :delete_domain_form, delete_domain_form())}
    end
  end

  defp rotate_domain_key(socket, project) do
    case Errors.rotate_domain_key(project, socket.assigns.domain) do
      {:ok, key} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext(
             "dashboard_domains",
             "Rotated. Update your Sentry-compatible client to the new Data Source Name."
           )
         )
         |> assign(:domain_keys, Map.put(socket.assigns.domain_keys, project.id, key))}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_domains", "Could not rotate the Data Source Name.")
         )}
    end
  end

  defp update_domain(socket, params) do
    case Domains.update_domain(socket.assigns.domain, params) do
      {:ok, domain} ->
        domain = Domains.get_domain!(domain.id)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_domains", "Domain updated."))
         |> assign(
           :page_title,
           dgettext("dashboard_domains", "%{domain} · Domains · %{product}",
             domain: domain.name,
             product: socket.assigns.product_name
           )
         )
         |> assign(:domain, domain)
         |> assign(OpenGraph.assigns(open_graph(domain)))
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
      member?={@member?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
      specs_have_new_activity?={@specs_have_new_activity?}
    >
      <DomainComponents.domain_detail
        domain={@domain}
        editable?={@editable?}
        admin?={@admin?}
        errors_enabled?={@errors_enabled?}
        domain_keys={@domain_keys}
        form={@form}
        delete_domain_form={@delete_domain_form}
      />
    </Layouts.dashboard>
    """
  end
end

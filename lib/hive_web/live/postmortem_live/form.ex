defmodule HiveWeb.PostmortemLive.Form do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Postmortems
  alias Hive.Postmortems.Postmortem
  alias Hive.Domains
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def slack_unfurl(uri, _params) do
    Hive.Slack.Unfurl.BlockKit.open_graph(uri, %{
      description:
        dgettext("dashboard_postmortems", "Publish or edit an incident postmortem in Markdown."),
      section_label: dgettext("dashboard_postmortems", "Postmortem"),
      highlights: [dgettext("dashboard_postmortems", "Markdown body")],
      id: "postmortem-form",
      path: "/postmortems",
      title: dgettext("dashboard_postmortems", "Postmortems")
    })
  end

  @impl true
  def mount(params, _session, socket) do
    postmortem =
      if socket.assigns.live_action == :edit,
        do: Postmortems.get_postmortem_by_number!(params["number"]),
        else: %Postmortem{}

    domains = Domains.list_visible_domains(socket.assigns.current_user)

    postmortem = %{postmortem | domain_ids: Enum.map(postmortem.domains || [], & &1.id)}

    if (socket.assigns.live_action == :new &&
          Postmortems.can_publish?(socket.assigns.current_user)) ||
         (socket.assigns.live_action == :edit &&
            Postmortems.can_edit?(postmortem, socket.assigns.current_user)) do
      title =
        if socket.assigns.live_action == :new,
          do: dgettext("dashboard_postmortems", "Publish postmortem"),
          else: dgettext("dashboard_postmortems", "Edit postmortem")

      {:ok,
       socket
       |> assign(:page_title, "#{title} · #{socket.assigns.product_name}")
       |> assign(OpenGraph.assigns(open_graph(title, params)))
       |> assign(:postmortem, postmortem)
       |> assign(:domains, domains)
       |> assign(:selected_domain_ids, postmortem.domain_ids)
       |> assign_form(Postmortems.change_postmortem(postmortem))}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         dgettext("dashboard_postmortems", "Only organization members can publish postmortems.")
       )
       |> redirect(to: ~p"/postmortems")}
    end
  end

  defp open_graph(title, %{"number" => number}),
    do: %{
      description: dgettext("dashboard_postmortems", "Edit a published incident postmortem."),
      section_label: dgettext("dashboard_postmortems", "Postmortem"),
      highlights: [dgettext("dashboard_postmortems", "Markdown body")],
      id: "postmortem-edit-#{number}",
      path: "/postmortems/#{number}/edit",
      title: title
    }

  defp open_graph(title, _params),
    do: %{
      description:
        dgettext("dashboard_postmortems", "Publish an incident postmortem in Markdown."),
      section_label: dgettext("dashboard_postmortems", "Postmortem"),
      highlights: [dgettext("dashboard_postmortems", "Markdown body")],
      id: "postmortem-new",
      path: "/postmortems/new",
      title: title
    }

  @impl true
  def handle_event("validate", %{"postmortem" => params}, socket) do
    {:noreply,
     socket
     |> assign(:selected_domain_ids, selected_domain_ids(params))
     |> assign_form(
       Postmortems.change_postmortem(socket.assigns.postmortem, params)
       |> Map.put(:action, :validate)
     )}
  end

  def handle_event("toggle_domain", %{"data" => domain_id}, socket) do
    selected_domain_ids =
      if domain_id in socket.assigns.selected_domain_ids,
        do: List.delete(socket.assigns.selected_domain_ids, domain_id),
        else: [domain_id | socket.assigns.selected_domain_ids]

    {:noreply, assign(socket, :selected_domain_ids, selected_domain_ids)}
  end

  def handle_event("save", %{"postmortem" => params}, socket) do
    result =
      if socket.assigns.live_action == :new,
        do: Postmortems.publish_postmortem(params, socket.assigns.current_user),
        else:
          Postmortems.update_postmortem(
            socket.assigns.postmortem,
            params,
            socket.assigns.current_user
          )

    case result do
      {:ok, postmortem} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_postmortems", "Postmortem published."))
         |> push_navigate(to: ~p"/postmortems/#{postmortem.number}")}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_postmortems", "Only organization members can publish postmortems.")
         )}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: :postmortem))

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
      <section id="postmortems">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{if @live_action == :new, do: dgettext("dashboard_postmortems", "Publish postmortem"), else: dgettext("dashboard_postmortems", "Edit postmortem")}</h1>
            <p>{dgettext("dashboard_postmortems", "Write the complete postmortem in Markdown. Its first level-one heading becomes the display title.")}</p>
          </div>
        </div>
        <.card icon="alert_triangle" title={dgettext("dashboard_postmortems", "Postmortem")}>
          <.card_section>
            <.form for={@form} id="postmortem-form" phx-change="validate" phx-submit="save">
              <.text_area
                field={@form[:body]}
                label={dgettext("dashboard_postmortems", "Markdown body")}
                placeholder={"# Incident title\n\nWhat happened?"}
                rows={20}
                max_length={100_000}
              />
              <div data-part="select-field">
                <span>{dgettext("dashboard_postmortems", "Domains")}</span>
                <input :for={domain_id <- @selected_domain_ids} type="hidden" name="postmortem[domain_ids][]" value={domain_id} />
                <.dropdown id="postmortem-domains" label={domain_label(@domains, @selected_domain_ids)} close_on_select={false}>
                  <.dropdown_item :for={domain <- @domains} value={domain.id} label={domain.name} checked={domain.id in @selected_domain_ids} on_click="toggle_domain" />
                </.dropdown>
              </div>
              <div data-part="select-field">
                <span>{dgettext("dashboard_postmortems", "Visibility")}</span>
                <.select id="postmortem-visibility" name={@form[:visibility].name} value={to_string(@form[:visibility].value)} label={dgettext("dashboard_postmortems", "Choose visibility")}>
                  <:item value="public" label={dgettext("dashboard_postmortems", "Public")} />
                  <:item value="private" label={dgettext("dashboard_postmortems", "Private")} />
                </.select>
              </div>
              <div data-part="form-actions">
                <.button
                  label={if @live_action == :new, do: dgettext("dashboard_postmortems", "Publish"), else: dgettext("dashboard_postmortems", "Save changes")}
                  size="medium"
                  variant="primary"
                  type="submit"
                />
              </div>
            </.form>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  defp selected_domain_ids(params) do
    params
    |> Map.get("domain_ids", [])
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp domain_label(_domains, []), do: dgettext("dashboard_postmortems", "Select domains")

  defp domain_label(domains, selected_domain_ids) do
    domains
    |> Enum.filter(&(&1.id in selected_domain_ids))
    |> Enum.map_join(", ", & &1.name)
  end
end

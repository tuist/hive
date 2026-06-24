defmodule HiveWeb.OpsLive.Drops do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  alias Hive.Audit
  alias Hive.Drops
  alias Hive.Drops.DropSource
  alias Hive.Drops.RssSyncer
  alias Hive.Ops.Policy
  alias Hive.Projects
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description:
        "Register RSS/Atom changelog sources for each domain. GitHub Releases is implicit.",
      section_label: "Ops",
      highlights: ["RSS / Atom sources", "Per-domain registration", "Polled every 15 minutes"],
      id: "ops-drops",
      path: "/ops/drops",
      title: "Drops"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Log in to manage drop sources.")
         |> redirect(to: ~p"/login?return_to=/ops/drops")}

      not Policy.authorize?(:drop_source_manage, user, nil) ->
        {:ok,
         socket
         |> put_flash(:error, "Only instance admins can manage drop sources.")
         |> push_navigate(to: ~p"/")}

      true ->
        {:ok,
         socket
         |> assign(:page_title, "Drops · #{socket.assigns.product_name}")
         |> assign(OpenGraph.assigns(open_graph()))
         |> assign(:sources, Drops.list_drop_sources())
         |> assign(:projects, Projects.list_projects())
         |> assign_source_form(Drops.change_drop_source(%DropSource{}, %{}))}
    end
  end

  @impl true
  def handle_event("validate", %{"drop_source" => params}, socket) do
    changeset =
      %DropSource{}
      |> Drops.change_drop_source(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_source_form(socket, changeset)}
  end

  def handle_event("create", %{"drop_source" => params}, socket) do
    case Drops.create_drop_source(params) do
      {:ok, source} ->
        record_audit(:"drop_source.added", source)

        {:noreply,
         socket
         |> put_flash(:info, "Source added.")
         |> assign(:sources, Drops.list_drop_sources())
         |> assign_source_form(Drops.change_drop_source(%DropSource{}, %{}))
         |> push_event("close-modal", %{id: "new-drop-source-modal"})}

      {:error, changeset} ->
        {:noreply, assign_source_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    source = Drops.get_drop_source!(id)

    case Drops.update_drop_source(source, %{"enabled" => !source.enabled}) do
      {:ok, updated} ->
        record_audit(:"drop_source.updated", updated)

        {:noreply,
         socket
         |> put_flash(
           :info,
           if(updated.enabled, do: "Source enabled.", else: "Source disabled.")
         )
         |> assign(:sources, Drops.list_drop_sources())}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update source.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    source = Drops.get_drop_source!(id)

    case Drops.delete_drop_source(source) do
      {:ok, deleted} ->
        record_audit(:"drop_source.removed", deleted)

        {:noreply,
         socket
         |> put_flash(:info, "Source removed.")
         |> assign(:sources, Drops.list_drop_sources())}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to remove source.")}
    end
  end

  def handle_event("sync", %{"id" => id}, socket) do
    source = Drops.get_drop_source!(id)

    Task.start(fn -> RssSyncer.sync_source(source) end)

    {:noreply,
     socket
     |> put_flash(:info, "Sync started for #{source.url}.")}
  end

  def handle_event("cancel_new_source", _params, socket) do
    {:noreply,
     socket
     |> assign_source_form(Drops.change_drop_source(%DropSource{}, %{}))
     |> push_event("close-modal", %{id: "new-drop-source-modal"})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.ops
      flash={@flash}
      product_name={@product_name}
      user_name={@user_name}
      user_email={@user_email}
      avatar_color={@avatar_color}
      signed_in?={@signed_in?}
      csrf_token={@csrf_token}
      current_path={@current_path}
    >
      <section id="ops-drops">
        <div data-part="page-header">
          <div data-part="title-group">
            <h1>Drops</h1>
            <p>
              Register RSS/Atom changelog feeds. Each ingested entry is routed to one or
              more domains by the classifier. GitHub Releases for any linked repository
              are ingested automatically and don't need a source here.
            </p>
          </div>
        </div>

        <.card icon="rss" title="RSS sources" data-part="sources-card">
          <:actions>
            <.new_drop_source_modal source_form={@source_form} projects={@projects} />
          </:actions>

          <.card_section data-part="sources-section">
            <div data-part="sources-table">
              <.table
                id="drop-sources-table"
                rows={@sources}
                row_key={fn source -> "drop-source-#{source.id}" end}
              >
                <:col :let={source} label="Source">
                  <.text_and_description_cell
                    icon="rss"
                    label={source_label(source)}
                    description={source.url}
                  />
                </:col>
                <:col :let={source} label="Status">
                  <.badge_cell
                    label={source_status_label(source)}
                    color={source_status_color(source)}
                    style="light-fill"
                  />
                </:col>
                <:col :let={source} label="Last poll">
                  <.text_cell
                    :if={source.last_error}
                    label={source_poll_label(source)}
                    sublabel={source.last_error}
                  />
                  <.text_cell :if={is_nil(source.last_error)} label={source_poll_label(source)} />
                </:col>
                <:col :let={source} label="">
                  <.button_cell>
                    <:button>
                      <.dropdown id={"drop-source-actions-#{source.id}"} icon_only>
                        <:icon><.dots_vertical /></:icon>
                        <.dropdown_item
                          label="Sync now"
                          value="sync"
                          on_click="sync"
                          phx-value-id={source.id}
                        >
                          <:left_icon><.reload /></:left_icon>
                        </.dropdown_item>
                        <.dropdown_item
                          label={if source.enabled, do: "Disable", else: "Enable"}
                          value="toggle_enabled"
                          on_click="toggle_enabled"
                          phx-value-id={source.id}
                        />
                        <.dropdown_item
                          label="Remove"
                          value="remove"
                          on_click="delete"
                          phx-value-id={source.id}
                          data-confirm={"Remove the source #{source_label(source)}?"}
                        >
                          <:left_icon><.trash /></:left_icon>
                        </.dropdown_item>
                      </.dropdown>
                    </:button>
                  </.button_cell>
                </:col>
                <:empty_state>
                  <.table_empty_state
                    icon="rss"
                    title="No RSS sources registered"
                    subtitle="Add a source to start ingesting changelog feed entries."
                  />
                </:empty_state>
              </.table>
            </div>
          </.card_section>
        </.card>
      </section>
    </Layouts.ops>
    """
  end

  defp source_label(source), do: source.label || source.url

  defp source_status_label(%DropSource{enabled: true}), do: "Enabled"
  defp source_status_label(%DropSource{enabled: false}), do: "Disabled"

  defp source_status_color(%DropSource{enabled: true}), do: "success"
  defp source_status_color(%DropSource{enabled: false}), do: "neutral"

  defp source_poll_label(%DropSource{last_polled_at: nil}), do: "Never"

  defp source_poll_label(%DropSource{last_polled_at: last_polled_at}) do
    Calendar.strftime(last_polled_at, "%Y-%m-%d %H:%M UTC")
  end

  attr :source_form, :map, required: true
  attr :projects, :list, required: true

  defp new_drop_source_modal(assigns) do
    ~H"""
    <.modal
      id="new-drop-source-modal"
      title="Add an RSS source"
      description="Register an RSS or Atom changelog feed. Hive routes each ingested entry to one or more domains automatically."
      header_type="icon"
      header_size="large"
      on_dismiss="cancel_new_source"
    >
      <:trigger :let={attrs}>
        <.button label="Add source" size="medium" variant="primary" {attrs}>
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="rss" />
      </:header_icon>

      <.form
        id="new-drop-source-form"
        for={@source_form}
        phx-change="validate"
        phx-submit="create"
        data-part="form"
      >
        <div :if={@projects == []} data-part="empty-projects">
          <p>Create a project first; sources are routed into a project's domains.</p>
        </div>

        <div :if={@projects != []} data-part="select-field">
          <span>Project</span>
          <.select
            id="new-drop-source-project"
            name={@source_form[:project_id].name}
            value={Phoenix.HTML.Form.normalize_value("select", @source_form[:project_id].value)}
            label="Choose project"
          >
            <:item :for={project <- @projects} value={project.id} label={project.name} />
          </.select>
        </div>

        <.text_input
          id="new-drop-source-url"
          field={@source_form[:url]}
          label="Feed URL"
          placeholder="https://example.com/changelog.atom"
        />
        <.text_input
          id="new-drop-source-label"
          field={@source_form[:label]}
          label="Label (optional)"
          placeholder="Example product changelog"
        />
      </.form>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label="Cancel"
              variant="secondary"
              size="medium"
              type="button"
              phx-click="cancel_new_source"
            />
          </:action>
          <:action>
            <.button
              label="Add"
              size="medium"
              variant="primary"
              type="submit"
              form="new-drop-source-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp assign_source_form(socket, changeset) do
    assign(socket, :source_form, to_form(changeset, as: :drop_source))
  end

  defp record_audit(action, %DropSource{} = source) do
    Audit.record(action, %{
      target_type: "drop_source",
      target_id: source.id,
      target_label: source.label || source.url,
      metadata: %{
        url: source.url,
        path: "/ops/drops"
      }
    })
  end
end

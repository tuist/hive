defmodule HiveWeb.SettingsSignalSourcesLive do
  use HiveWeb, :live_view
  use Noora

  import HiveWeb.CoreComponents, only: []

  alias Hive.Integrations
  alias Hive.Integrations.SlackIntegration

  def mount(_params, _session, socket) do
    integrations = Integrations.list_slack_integrations()

    socket =
      socket
      |> assign(:page_title, gettext("Settings"))
      |> assign(:integrations, integrations)
      |> assign(:show_add_form, false)
      |> assign_bot_form()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id="settings">
      <h1 data-part="title">{gettext("Settings")}</h1>

      <.tab_menu_horizontal>
        <.tab_menu_horizontal_item
          label={gettext("General")}
          selected={false}
          patch={~p"/settings"}
        />
        <.tab_menu_horizontal_item
          label={gettext("Signal Sources")}
          selected={true}
          patch={~p"/settings/signal-sources"}
        />
      </.tab_menu_horizontal>

      <h2 data-part="subtitle">{gettext("Signal Sources")}</h2>

      <.card title={gettext("Slack Bots")} icon="brand_slack" data-part="slack-card">
        <:actions>
          <.button
            label={gettext("Add Bot")}
            size="medium"
            phx-click="toggle_add_form"
          />
        </:actions>
        <.card_section data-part="slack-bots">
          <.form
            :if={@show_add_form}
            for={@bot_form}
            phx-submit="create_bot"
            data-part="bot-form"
          >
            <.text_input
              field={@bot_form[:name]}
              type="basic"
              label={gettext("Name")}
              placeholder={gettext("e.g. Community Support")}
            />
            <.text_input
              field={@bot_form[:bot_token]}
              type="basic"
              label={gettext("Bot Token")}
              placeholder="xoxb-..."
            />
            <div data-part="form-actions">
              <.button label={gettext("Create")} size="medium" type="submit" />
              <.button
                label={gettext("Cancel")}
                variant="secondary"
                size="medium"
                type="button"
                phx-click="toggle_add_form"
              />
            </div>
          </.form>

          <.table
            :if={@integrations != []}
            id="slack-bots-table"
            rows={@integrations}
            row_navigate={fn integration -> ~p"/settings/signal-sources/slack/#{integration.id}" end}
          >
            <:col :let={integration} label={gettext("Name")}>
              <.text_cell label={integration.name} />
            </:col>
            <:col :let={integration} label={gettext("Channels")}>
              <.badge_cell
                label={"#{length(integration.channels)}"}
                color="neutral"
              />
            </:col>
          </.table>

          <p :if={@integrations == [] && !@show_add_form} data-part="empty">
            {gettext("No Slack bots configured yet. Add one to start monitoring channels.")}
          </p>
        </.card_section>
      </.card>
    </div>
    """
  end

  def handle_event("toggle_add_form", _params, socket) do
    {:noreply, assign(socket, :show_add_form, !socket.assigns.show_add_form)}
  end

  def handle_event("create_bot", %{"slack_integration" => params}, socket) do
    case Integrations.create_slack_integration(params) do
      {:ok, _integration} ->
        {:noreply,
         socket
         |> assign(:integrations, Integrations.list_slack_integrations())
         |> assign(:show_add_form, false)
         |> assign_bot_form()
         |> put_flash(:info, gettext("Slack bot created."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :bot_form, to_form(changeset, as: "slack_integration"))}
    end
  end

  defp assign_bot_form(socket) do
    changeset = Integrations.change_slack_integration(%SlackIntegration{})
    assign(socket, :bot_form, to_form(changeset, as: "slack_integration"))
  end
end

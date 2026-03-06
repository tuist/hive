defmodule HiveWeb.SettingsSignalSourcesLive do
  use HiveWeb, :live_view
  use Noora

  import HiveWeb.CoreComponents, only: []

  alias Hive.Integrations
  alias Hive.Integrations.SlackIntegration
  alias Hive.Integrations.GitHubApp

  def mount(_params, _session, socket) do
    slack_integrations = Integrations.list_slack_integrations()
    github_apps = Integrations.list_github_apps()

    socket =
      socket
      |> assign(:page_title, gettext("Settings"))
      |> assign(:integrations, slack_integrations)
      |> assign(:github_apps, github_apps)
      |> assign(:show_add_form, false)
      |> assign(:show_add_github_form, false)
      |> assign_bot_form()
      |> assign_github_form()

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
            <.text_input
              field={@bot_form[:signing_secret]}
              type="basic"
              label={gettext("Signing Secret")}
              placeholder={gettext("Found in your Slack app's Basic Information page")}
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

      <.card title={gettext("GitHub Apps")} icon="brand_github" data-part="github-card">
        <:actions>
          <.button
            label={gettext("Add App")}
            size="medium"
            phx-click="toggle_add_github_form"
          />
        </:actions>
        <.card_section data-part="github-apps">
          <.form
            :if={@show_add_github_form}
            for={@github_form}
            phx-submit="create_github_app"
            data-part="bot-form"
          >
            <.text_input
              field={@github_form[:name]}
              type="basic"
              label={gettext("Name")}
              placeholder={gettext("e.g. My GitHub App")}
            />
            <.text_input
              field={@github_form[:webhook_secret]}
              type="basic"
              label={gettext("Webhook Secret")}
              placeholder={gettext("The secret configured in your GitHub App's webhook settings")}
            />
            <div data-part="form-actions">
              <.button label={gettext("Create")} size="medium" type="submit" />
              <.button
                label={gettext("Cancel")}
                variant="secondary"
                size="medium"
                type="button"
                phx-click="toggle_add_github_form"
              />
            </div>
          </.form>

          <.table
            :if={@github_apps != []}
            id="github-apps-table"
            rows={@github_apps}
            row_navigate={fn app -> ~p"/settings/signal-sources/github/#{app.id}" end}
          >
            <:col :let={app} label={gettext("Name")}>
              <.text_cell label={app.name} />
            </:col>
            <:col :let={app} label={gettext("Repositories")}>
              <.badge_cell
                label={"#{length(app.repositories)}"}
                color="neutral"
              />
            </:col>
          </.table>

          <p :if={@github_apps == [] && !@show_add_github_form} data-part="empty">
            {gettext("No GitHub apps configured yet. Add one to start monitoring repositories.")}
          </p>
        </.card_section>
      </.card>
    </div>
    """
  end

  def handle_event("toggle_add_form", _params, socket) do
    {:noreply, assign(socket, :show_add_form, !socket.assigns.show_add_form)}
  end

  def handle_event("toggle_add_github_form", _params, socket) do
    {:noreply, assign(socket, :show_add_github_form, !socket.assigns.show_add_github_form)}
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

  def handle_event("create_github_app", %{"github_app" => params}, socket) do
    case Integrations.create_github_app(params) do
      {:ok, _app} ->
        {:noreply,
         socket
         |> assign(:github_apps, Integrations.list_github_apps())
         |> assign(:show_add_github_form, false)
         |> assign_github_form()
         |> put_flash(:info, gettext("GitHub app created."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :github_form, to_form(changeset, as: "github_app"))}
    end
  end

  defp assign_bot_form(socket) do
    changeset = Integrations.change_slack_integration(%SlackIntegration{})
    assign(socket, :bot_form, to_form(changeset, as: "slack_integration"))
  end

  defp assign_github_form(socket) do
    changeset = Integrations.change_github_app(%GitHubApp{})
    assign(socket, :github_form, to_form(changeset, as: "github_app"))
  end
end

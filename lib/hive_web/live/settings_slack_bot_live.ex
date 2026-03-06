defmodule HiveWeb.SettingsSlackBotLive do
  use HiveWeb, :live_view
  use Noora

  import HiveWeb.CoreComponents, only: []

  alias Hive.Integrations

  def mount(%{"id" => id}, _session, socket) do
    case Integrations.get_slack_integration(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Slack bot not found."))
         |> push_navigate(to: ~p"/settings/signal-sources")}

      integration ->
        channels = Integrations.list_slack_channels(integration)

        socket =
          socket
          |> assign(:page_title, integration.name)
          |> assign(:integration, integration)
          |> assign(:channels, channels)
          |> assign(:show_edit_form, false)
          |> assign_bot_form(integration)
          |> assign_channel_form()

        {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="settings">
      <h1 data-part="title">{@integration.name}</h1>

      <.card title={gettext("Configuration")} icon="settings" data-part="config-card">
        <.card_section data-part="bot-config">
          <div :if={!@show_edit_form} data-part="bot-info">
            <div data-part="bot-details">
              <div data-part="bot-field">
                <span data-part="label">{gettext("Name")}</span>
                <span data-part="value">{@integration.name}</span>
              </div>
              <div data-part="bot-field">
                <span data-part="label">{gettext("Bot Token")}</span>
                <span data-part="value">{mask_token(@integration.bot_token)}</span>
              </div>
            </div>
            <div data-part="actions">
              <.button
                label={gettext("Edit")}
                variant="secondary"
                size="medium"
                phx-click="edit_bot"
              />
              <.button
                label={gettext("Delete Bot")}
                variant="destructive"
                size="medium"
                phx-click="delete_bot"
                data-confirm={
                  gettext("Are you sure? This will remove the bot and all its monitored channels.")
                }
              />
            </div>
          </div>

          <.form
            :if={@show_edit_form}
            for={@bot_form}
            phx-submit="update_bot"
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
              <.button label={gettext("Save")} size="medium" type="submit" />
              <.button
                label={gettext("Cancel")}
                variant="secondary"
                size="medium"
                type="button"
                phx-click="cancel_edit"
              />
            </div>
          </.form>
        </.card_section>
      </.card>

      <.card title={gettext("Monitored Channels")} icon="bell" data-part="channels-card">
        <.card_section data-part="monitored-channels">
          <.form for={@channel_form} phx-submit="add_channel" data-part="channel-form">
            <div data-part="channel-inputs">
              <.text_input
                field={@channel_form[:channel_id]}
                type="basic"
                label={gettext("Channel ID")}
                placeholder="C0123456789"
              />
              <.text_input
                field={@channel_form[:channel_name]}
                type="basic"
                label={gettext("Channel Name")}
                placeholder="#support"
              />
            </div>
            <.button label={gettext("Add Channel")} size="medium" type="submit" />
          </.form>

          <.table :if={@channels != []} id="slack-channels" rows={@channels}>
            <:col :let={channel} label={gettext("Channel")}>
              <.text_cell label={"#" <> channel.channel_name} />
            </:col>
            <:col :let={channel} label={gettext("Channel ID")}>
              <.text_cell label={channel.channel_id} />
            </:col>
            <:col :let={channel} label="">
              <.button
                label={gettext("Remove")}
                variant="destructive"
                size="small"
                phx-click="remove_channel"
                phx-value-id={channel.id}
              />
            </:col>
          </.table>

          <p :if={@channels == []} data-part="empty">
            {gettext("No channels being monitored yet.")}
          </p>
        </.card_section>
      </.card>
    </div>
    """
  end

  def handle_event("edit_bot", _params, socket) do
    {:noreply, assign(socket, :show_edit_form, true)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :show_edit_form, false)}
  end

  def handle_event("update_bot", %{"slack_integration" => params}, socket) do
    case Integrations.update_slack_integration(socket.assigns.integration, params) do
      {:ok, integration} ->
        integration = Hive.Repo.preload(integration, :channels)

        {:noreply,
         socket
         |> assign(:integration, integration)
         |> assign(:show_edit_form, false)
         |> assign(:page_title, integration.name)
         |> assign_bot_form(integration)
         |> put_flash(:info, gettext("Bot updated."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :bot_form, to_form(changeset, as: "slack_integration"))}
    end
  end

  def handle_event("delete_bot", _params, socket) do
    case Integrations.delete_slack_integration(socket.assigns.integration) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Slack bot deleted."))
         |> push_navigate(to: ~p"/settings/signal-sources")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete bot."))}
    end
  end

  def handle_event("add_channel", %{"slack_channel" => params}, socket) do
    case Integrations.add_slack_channel(socket.assigns.integration, atomize_keys(params)) do
      {:ok, _channel} ->
        channels = Integrations.list_slack_channels(socket.assigns.integration)

        {:noreply,
         socket
         |> assign(:channels, channels)
         |> assign_channel_form()
         |> put_flash(:info, gettext("Channel added."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :channel_form, to_form(changeset, as: "slack_channel"))}
    end
  end

  def handle_event("remove_channel", %{"id" => id}, socket) do
    case Integrations.delete_slack_channel(id) do
      {:ok, _} ->
        channels = Integrations.list_slack_channels(socket.assigns.integration)

        {:noreply,
         socket
         |> assign(:channels, channels)
         |> put_flash(:info, gettext("Channel removed."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to remove channel."))}
    end
  end

  defp assign_bot_form(socket, integration) do
    changeset = Integrations.change_slack_integration(integration)
    assign(socket, :bot_form, to_form(changeset, as: "slack_integration"))
  end

  defp assign_channel_form(socket) do
    changeset =
      Hive.Integrations.SlackChannel.changeset(%Hive.Integrations.SlackChannel{}, %{})

    assign(socket, :channel_form, to_form(changeset, as: "slack_channel"))
  end

  defp mask_token(token) when is_binary(token) do
    if String.length(token) > 8 do
      String.slice(token, 0, 8) <> "..."
    else
      "***"
    end
  end

  defp mask_token(_), do: "***"

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end

defmodule HiveWeb.SettingsLive do
  use HiveWeb, :live_view
  use Noora

  import HiveWeb.CoreComponents, only: []

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Settings"))}
  end

  def render(assigns) do
    ~H"""
    <div id="settings">
      <h1 data-part="title">{gettext("Settings")}</h1>

      <.tab_menu_horizontal>
        <.tab_menu_horizontal_item
          label={gettext("General")}
          selected={true}
          patch={~p"/settings"}
        />
        <.tab_menu_horizontal_item
          label={gettext("Signal Sources")}
          selected={false}
          patch={~p"/settings/signal-sources"}
        />
      </.tab_menu_horizontal>

      <h2 data-part="subtitle">{gettext("General")}</h2>

      <.card_section data-part="general">
        <div data-part="header">
          <span data-part="title">{gettext("Instance")}</span>
          <span data-part="subtitle">
            {gettext("General instance configuration and preferences.")}
          </span>
        </div>
      </.card_section>
    </div>
    """
  end
end

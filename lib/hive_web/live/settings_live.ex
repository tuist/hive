defmodule HiveWeb.SettingsLive do
  use HiveWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Settings"))}
  end

  def render(assigns) do
    ~H"""
    <h1>{gettext("Settings")}</h1>
    <p>{gettext("Instance configuration and preferences will appear here.")}</p>
    """
  end
end

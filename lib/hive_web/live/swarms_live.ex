defmodule HiveWeb.SwarmsLive do
  use HiveWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Swarms"))}
  end

  def render(assigns) do
    ~H"""
    <h1>{gettext("Swarms")}</h1>
    <p>{gettext("Active and past agentic sessions will appear here.")}</p>
    """
  end
end

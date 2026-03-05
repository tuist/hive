defmodule HiveWeb.SignalsLive do
  use HiveWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Signals"))}
  end

  def render(assigns) do
    ~H"""
    <h1>{gettext("Signals")}</h1>
    <p>
      {gettext(
        "GitHub issues, Linear tasks, Slack support requests, and other work items will appear here."
      )}
    </p>
    """
  end
end

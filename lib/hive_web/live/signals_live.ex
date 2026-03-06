defmodule HiveWeb.SignalsLive do
  use HiveWeb, :live_view
  use Noora

  import HiveWeb.CoreComponents, only: []

  alias Hive.Signals

  def mount(_params, _session, socket) do
    signals = Signals.list_signals()

    socket =
      socket
      |> assign(:page_title, gettext("Signals"))
      |> assign(:signals, signals)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id="signals">
      <h1 data-part="title">{gettext("Signals")}</h1>
      <p data-part="description">
        {gettext("Signals are messages from monitored Slack channels and other sources.")}
      </p>

      <.card :if={@signals != []} title={gettext("Recent Signals")} icon="bell">
        <.table id="signals-table" rows={@signals}>
          <:col :let={signal} label={gettext("Source")}>
            <.badge_cell label={signal.source} color="neutral" icon="brand_slack" />
          </:col>
          <:col :let={signal} label={gettext("Title")}>
            <.text_cell label={signal.title} />
          </:col>
          <:col :let={signal} label={gettext("Author")}>
            <.text_cell label={signal.source_author || "-"} />
          </:col>
          <:col :let={signal} label={gettext("Channel")}>
            <.text_cell label={signal.source_channel || "-"} />
          </:col>
          <:col :let={signal} label={gettext("Received")}>
            <.text_cell label={Calendar.strftime(signal.inserted_at, "%b %d, %Y %H:%M")} />
          </:col>
        </.table>
      </.card>

      <.card_section :if={@signals == []}>
        <div data-part="header">
          <span data-part="title">{gettext("No signals yet")}</span>
          <span data-part="subtitle">
            {gettext("Configure a Slack integration in Settings to start monitoring channels.")}
          </span>
        </div>
      </.card_section>
    </div>
    """
  end
end

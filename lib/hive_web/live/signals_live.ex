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
        <.table
          id="signals-table"
          rows={@signals}
          row_navigate={fn signal -> ~p"/signals/#{signal.id}" end}
        >
          <:col :let={signal} label={gettext("Source")}>
            <.badge_cell label={signal.source} color="neutral" icon={source_icon(signal.source)} />
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
            <.text_cell label={format_timestamp(signal.source_timestamp || signal.inserted_at)} />
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

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%b %d, %Y %H:%M UTC")
  end

  defp source_icon("github"), do: "brand_github"
  defp source_icon("slack"), do: "brand_slack"
  defp source_icon(_source), do: "bell"
end

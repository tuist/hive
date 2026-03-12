defmodule HiveWeb.SignalLive do
  use HiveWeb, :live_view
  use Noora

  import HiveWeb.CoreComponents, only: []

  alias Hive.Markdown
  alias Hive.Signals

  def mount(%{"id" => id}, _session, socket) do
    case Signals.get_signal(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Signal not found."))
         |> push_navigate(to: ~p"/signals")}

      signal ->
        {:ok,
         socket
         |> assign(:page_title, signal.title)
         |> assign(:signal, signal)}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="signal">
      <.link navigate={~p"/signals"} data-part="back-link">
        {gettext("Back to signals")}
      </.link>

      <div data-part="header">
        <div data-part="title-group">
          <h1 data-part="title">{@signal.title}</h1>
          <p data-part="description">
            {gettext("Follow the original signal and the conversation that happened around it.")}
          </p>
        </div>

        <.link
          :if={@signal.source_url}
          id="signal-source-link"
          href={@signal.source_url}
          target="_blank"
          rel="noopener noreferrer"
        >
          <.button label={source_link_label(@signal.source)} variant="secondary" size="small" />
        </.link>
      </div>

      <.card title={gettext("Signal")} icon={source_icon(@signal.source)} data-part="signal-card">
        <.card_section>
          <div data-part="metadata">
            <div data-part="meta-item">
              <span data-part="label">{gettext("Source")}</span>
              <span data-part="value">{source_name(@signal.source)}</span>
            </div>
            <div data-part="meta-item">
              <span data-part="label">{gettext("Author")}</span>
              <span data-part="value">{@signal.source_author || "-"}</span>
            </div>
            <div data-part="meta-item">
              <span data-part="label">{gettext("Channel")}</span>
              <span data-part="value">{@signal.source_channel || "-"}</span>
            </div>
            <div data-part="meta-item">
              <span data-part="label">{gettext("Received")}</span>
              <span data-part="value">
                {format_timestamp(@signal.source_timestamp || @signal.inserted_at)}
              </span>
            </div>
          </div>

          <div :if={present?(@signal.body)} class="signal-markdown" data-part="body">
            {render_markdown(@signal.body)}
          </div>
        </.card_section>
      </.card>

      <.card
        title={gettext("Conversation")}
        icon="bell"
        data-part="conversation-card"
      >
        <.card_section>
          <div id="signal-conversation" data-part="conversation">
            <p
              :if={@signal.messages == []}
              id="signal-empty-conversation"
              data-part="empty-conversation"
            >
              {gettext("No replies yet.")}
            </p>

            <article
              :for={message <- @signal.messages}
              id={"message-#{message.id}"}
              data-part="message"
            >
              <div data-part="message-header">
                <div data-part="message-meta">
                  <p data-part="message-author">{message.author || "-"}</p>
                  <p data-part="message-timestamp">
                    {format_timestamp(message.source_timestamp || message.inserted_at)}
                  </p>
                </div>

                <.link
                  :if={message.source_url}
                  id={"message-source-link-#{message.id}"}
                  href={message.source_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  data-part="message-source-link"
                >
                  {source_link_label(@signal.source)}
                </.link>
              </div>

              <div class="signal-markdown" data-part="body">
                {render_markdown(message.body)}
              </div>
            </article>
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp render_markdown(markdown) do
    markdown
    |> Markdown.to_html!()
    |> raw()
  end

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%b %d, %Y %H:%M UTC")
  end

  defp source_icon("github"), do: "brand_github"
  defp source_icon("slack"), do: "brand_slack"
  defp source_icon(_source), do: "bell"

  defp source_link_label("github"), do: gettext("Open on GitHub")
  defp source_link_label("slack"), do: gettext("Open in Slack")
  defp source_link_label(_source), do: gettext("Open source")

  defp source_name("github"), do: "GitHub"
  defp source_name("slack"), do: "Slack"
  defp source_name(source), do: source
end

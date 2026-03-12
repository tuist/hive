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
      <div data-part="action-buttons">
        <.button
          id="signal-back-button"
          label={gettext("Signals")}
          variant="secondary"
          size="medium"
          navigate={~p"/signals"}
        >
          <:icon_left>
            <.icon name="arrow_left" />
          </:icon_left>
        </.button>
        <.button
          :if={@signal.source_url}
          id="signal-source-link"
          href={@signal.source_url}
          target="_blank"
          rel="noopener noreferrer"
          label={source_link_label(@signal.source)}
          variant="secondary"
          size="medium"
        >
          <:icon_right>
            <.icon name="external_link" />
          </:icon_right>
        </.button>
      </div>

      <div data-part="header">
        <div data-part="title">
          <h1 data-part="label">{@signal.title}</h1>
          <div data-part="meta">
            <.source_badge source={@signal.source} size="large" />
            <.signal_status_badge status={@signal.status} size="large" />
            <span data-part="meta-text">{conversation_count_label(length(@signal.messages))}</span>
          </div>
        </div>
      </div>

      <.card title={gettext("Details")} icon={source_icon(@signal.source)} data-part="details-card">
        <.card_section data-part="details-card-section">
          <div data-part="metadata-grid">
            <div data-part="metadata-row">
              <.metadata_item title={gettext("Source")}>
                <.source_badge source={@signal.source} />
              </.metadata_item>
              <.metadata_item title={gettext("Status")}>
                <.signal_status_badge status={@signal.status} />
              </.metadata_item>
              <.metadata_item title={gettext("Author")}>
                {@signal.source_author || "-"}
              </.metadata_item>
            </div>
            <div data-part="metadata-row">
              <.metadata_item title={gettext("Channel")}>
                {@signal.source_channel || "-"}
              </.metadata_item>
              <.metadata_item title={gettext("Received")}>
                {format_timestamp(@signal.source_timestamp || @signal.inserted_at)}
              </.metadata_item>
            </div>
          </div>
        </.card_section>

        <.card_section :if={present?(@signal.body)} data-part="body-card-section">
          <div class="signal-markdown" data-part="body">
            {render_markdown(@signal.body)}
          </div>
        </.card_section>
      </.card>

      <.card
        title={gettext("Conversation")}
        icon="file"
        data-part="conversation-card"
      >
        <.card_section
          :if={@signal.messages == []}
          id="signal-empty-conversation"
          data-part="conversation-empty-section"
        >
          <span data-part="empty-conversation">{gettext("No replies yet.")}</span>
        </.card_section>

        <.card_section
          :for={message <- @signal.messages}
          id={"message-#{message.id}"}
          data-part="conversation-message-section"
        >
          <div data-part="message-header">
            <div data-part="message-meta">
              <p data-part="message-author">{message.author || "-"}</p>
              <p data-part="message-timestamp">
                {format_timestamp(message.source_timestamp || message.inserted_at)}
              </p>
            </div>

            <.link_button
              :if={message.source_url}
              id={"message-source-link-#{message.id}"}
              href={message.source_url}
              target="_blank"
              label={message_source_link_label(@signal.source)}
              variant="secondary"
              size="small"
              underline
              data-part="message-source-link"
            >
              <:icon_right>
                <.icon name="external_link" />
              </:icon_right>
            </.link_button>
          </div>

          <div class="signal-markdown" data-part="body">
            {render_markdown(message.body)}
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp metadata_item(assigns) do
    ~H"""
    <div data-part="metadata">
      <div data-part="title">{@title}</div>
      <span data-part="label">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  attr :source, :string, required: true
  attr :size, :string, default: "small"

  defp source_badge(assigns) do
    ~H"""
    <.badge label={source_name(@source)} color="neutral" style="light-fill" size={@size}>
      <:icon>
        <.icon name={source_icon(@source)} />
      </:icon>
    </.badge>
    """
  end

  attr :status, :atom, required: true
  attr :size, :string, default: "small"

  defp signal_status_badge(assigns) do
    ~H"""
    <.badge
      label={status_label(@status)}
      color={status_color(@status)}
      style="light-fill"
      size={@size}
    />
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

  defp message_source_link_label("github"), do: gettext("View comment")
  defp message_source_link_label("slack"), do: gettext("View reply")
  defp message_source_link_label(_source), do: gettext("Open source")

  defp status_label(:new), do: gettext("New")
  defp status_label(:in_flight), do: gettext("In Flight")
  defp status_label(:needs_review), do: gettext("Needs Review")
  defp status_label(:resolved), do: gettext("Resolved")
  defp status_label(:ignored), do: gettext("Ignored")
  defp status_label(_status), do: gettext("New")

  defp status_color(:new), do: "information"
  defp status_color(:in_flight), do: "focus"
  defp status_color(:needs_review), do: "warning"
  defp status_color(:resolved), do: "success"
  defp status_color(:ignored), do: "neutral"
  defp status_color(_status), do: "neutral"

  defp conversation_count_label(count) do
    ngettext("%{count} follow-up", "%{count} follow-ups", count, count: count)
  end

  defp source_name("github"), do: "GitHub"
  defp source_name("slack"), do: "Slack"
  defp source_name(source) when is_binary(source), do: String.capitalize(source)
  defp source_name(_source), do: "Signal"
end

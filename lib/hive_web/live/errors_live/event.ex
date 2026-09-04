defmodule HiveWeb.ErrorsLive.Event do
  @moduledoc """
  Detail page for a single event captured under an issue. Renders the
  same panels as the issue detail page (Tags, Contexts, Request,
  Breadcrumbs, Additional data, Modules, SDK, Stack trace) but scoped
  to the specific event referenced in the URL rather than the latest.
  """

  use HiveWeb, :live_view
  use Noora

  @behaviour Hive.Slack.Unfurl

  import HiveWeb.ErrorsLive.EventPanels
  import HiveWeb.PlatformIcon

  alias Hive.Errors
  alias Hive.Errors.Issue
  alias Hive.Errors.Policy
  alias Hive.Slack.Unfurl.BlockKit
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  @impl Hive.Slack.Unfurl
  def slack_unfurl(uri, %{"id" => id, "event_id" => event_id}) do
    with {:ok, issue} <- Errors.fetch_issue(id),
         %{} = event <- Errors.fetch_event(issue.id, event_id) do
      BlockKit.open_graph(uri, event_open_graph(issue, event, event_id))
    else
      _ -> :skip
    end
  end

  defp event_open_graph(issue, event, event_id) do
    short = short_id(event[:event_id] || event_id)

    %{
      description:
        dgettext(
          "dashboard_errors",
          "Event %{short} on %{issue}. Captured %{timestamp}.",
          short: short,
          issue: issue.title,
          timestamp: format_datetime(event[:timestamp])
        ),
      section_label: dgettext("dashboard_errors", "Errors"),
      highlights:
        Enum.reject(
          [
            short,
            project_name(issue),
            to_string(event[:environment] || ""),
            to_string(event[:release] || "")
          ],
          &(&1 == "")
        ),
      id: "error-event-#{event_id}",
      path: "/errors/#{issue.id}/events/#{event_id}",
      title: dgettext("dashboard_errors", "Event %{short}", short: short)
    }
  end

  @impl true
  def mount(%{"id" => id, "event_id" => event_id}, _session, socket) do
    user = socket.assigns[:current_user]

    with true <- Policy.authorize?(:error_issue_read, user, nil) || :unauthorized,
         {:ok, issue} <- Errors.fetch_issue(id),
         %{} = event <- Errors.fetch_event(issue.id, event_id) do
      payload = event[:payload] || %{}

      {:ok,
       socket
       |> assign(:issue, issue)
       |> assign(:event, event)
       |> assign(:payload, payload)
       |> assign(
         :page_title,
         dgettext(
           "dashboard_errors",
           "Event %{event_id} · %{title} · %{product}",
           event_id: short_id(event[:event_id] || event_id),
           title: issue.title,
           product: socket.assigns.product_name
         )
       )
       |> assign(
         OpenGraph.assigns(%{
           description: issue.title,
           section_label: dgettext("dashboard_errors", "Errors"),
           highlights: [
             short_id(event[:event_id] || event_id),
             project_name(issue),
             to_string(event[:environment] || "")
           ],
           id: "error-event-#{event_id}",
           path: "/errors/#{issue.id}/events/#{event_id}",
           title:
             dgettext("dashboard_errors", "Event %{short}",
               short: short_id(event[:event_id] || event_id)
             )
         })
       )}
    else
      :unauthorized ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_errors", "You do not have access to errors."))
         |> push_navigate(to: ~p"/")}

      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_errors", "Event not found."))
         |> push_navigate(to: ~p"/errors/#{id}")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_errors", "Issue not found."))
         |> push_navigate(to: ~p"/errors")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      product_name={@product_name}
      user_name={@user_name}
      user_email={@user_email}
      avatar_color={@avatar_color}
      auth_enabled?={@auth_enabled?}
      signed_in?={@signed_in?}
      admin?={@admin?}
      member?={@member?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
      specs_have_new_activity?={@specs_have_new_activity?}
    >
      <section id="error-event">
        <div data-part="header">
          <div data-part="title-group">
            <div data-part="breadcrumbs">
              <.link navigate={~p"/errors"}>{dgettext("dashboard_errors", "Errors")}</.link>
              <span data-part="separator">/</span>
              <.link navigate={~p"/errors/#{@issue.id}"}>
                {truncate_display(@issue.title, 60)}
              </.link>
              <span data-part="separator">/</span>
              <span>
                {dgettext("dashboard_errors", "Event %{short}",
                  short: short_id(@event.event_id)
                )}
              </span>
            </div>
            <h1>
              <.platform_icon platform={to_string(@issue.platform)} size="medium" />
              <span>{event_headline(@event, @payload)}</span>
            </h1>
            <p data-part="event-meta-header">
              <span>{format_datetime(@event.timestamp)}</span>
              <span :if={present?(@event.environment)}>· {@event.environment}</span>
              <span :if={present?(@event.release)}>
                · {dgettext("dashboard_errors", "Release %{release}", release: @event.release)}
              </span>
            </p>
          </div>
        </div>

        <.card
          :if={stack_frames(@payload) != []}
          title={dgettext("dashboard_errors", "Stack trace")}
          icon="alert_triangle"
        >
          <.card_section>
            <div data-part="stack-frames">
              <div
                :for={frame <- stack_frames(@payload)}
                data-part="frame"
                data-in-app={to_string(frame["in_app"] == true)}
              >
                <div data-part="frame-header">
                  <span data-part="frame-indicator" title={
                    if frame["in_app"] == true,
                      do: dgettext("dashboard_errors", "In-app frame"),
                      else: dgettext("dashboard_errors", "External frame")
                  } />
                  <span data-part="frame-mfa">
                    <span :if={frame["module"]} data-part="frame-module">{frame["module"]}</span><span :if={frame["module"] && frame["function"]}>.</span><span data-part="frame-function">{frame["function"] || "?"}</span>
                  </span>
                  <span :if={frame["filename"]} data-part="frame-location">
                    {frame["filename"]}<span :if={frame["lineno"]}>:{frame["lineno"]}</span>
                  </span>
                </div>
                <div :if={highlighted_frame(frame, @payload)} data-part="context">
                  {Phoenix.HTML.raw(highlighted_frame(frame, @payload))}
                </div>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={stack_frames(@payload) == [] && latest_message(@payload)}
          title={dgettext("dashboard_errors", "Message")}
          icon="info_circle"
        >
          <.card_section>
            <pre data-part="message-body">{latest_message(@payload)}</pre>
          </.card_section>
        </.card>

        <.tags_card issue={@issue} payload={@payload} />
        <.contexts_card payload={@payload} />
        <.request_card payload={@payload} />
        <.breadcrumbs_card payload={@payload} />
        <.additional_data_card payload={@payload} />
        <.modules_card payload={@payload} />
        <.sdk_card payload={@payload} />
      </section>
    </Layouts.dashboard>
    """
  end

  ## Local helpers

  defp event_headline(event, payload) do
    cond do
      present?(event[:exception_type]) and present?(event[:exception_value]) ->
        "#{event.exception_type}: #{event.exception_value}"

      present?(event[:exception_type]) ->
        event.exception_type

      msg = latest_message(payload) ->
        truncate_display(msg, 140)

      true ->
        dgettext("dashboard_errors", "Event %{short}", short: short_id(event[:event_id]))
    end
  end

  defp short_id(nil), do: "?"

  defp short_id(id) when is_binary(id) do
    id
    |> String.replace("-", "")
    |> String.slice(0, 8)
  end

  defp short_id(other), do: other |> to_string() |> short_id()

  defp stack_frames(%{
         "exception" => %{"values" => [%{"stacktrace" => %{"frames" => frames}} | _]}
       })
       when is_list(frames) do
    frames |> Enum.reverse() |> Enum.take(30)
  end

  defp stack_frames(_), do: []

  defp highlighted_frame(frame, payload) do
    platform = Map.get(payload, "platform")
    Hive.Errors.CodeHighlight.highlight_frame(frame, platform)
  end

  defp latest_message(payload) do
    case payload["message"] do
      %{"formatted" => formatted} when is_binary(formatted) and formatted != "" -> formatted
      %{"message" => message} when is_binary(message) and message != "" -> message
      msg when is_binary(msg) and msg != "" -> msg
      _ -> nil
    end
  end

  defp present?(value) when is_binary(value) and byte_size(value) > 0, do: true
  defp present?(_), do: false

  defp project_name(%Issue{project: %{name: name}}), do: name
  defp project_name(_), do: "-"

  defp truncate_display(nil, _), do: ""

  defp truncate_display(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end
end

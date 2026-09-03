defmodule HiveWeb.ErrorsLive.Show do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  alias Hive.Errors
  alias Hive.Errors.Issue
  alias Hive.Errors.Policy
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph(issue) do
    %{
      description:
        dgettext(
          "dashboard_errors",
          "%{count} events across %{project}. Last seen %{last_seen}.",
          count: issue.event_count,
          project: project_name(issue),
          last_seen: format_datetime(issue.last_seen)
        ),
      section_label: dgettext("dashboard_errors", "Errors"),
      highlights: [
        Integer.to_string(issue.event_count),
        project_name(issue),
        status_label(issue.status)
      ],
      id: "error-issue-#{issue.id}",
      path: "/errors/#{issue.id}",
      title: issue.title
    }
  end

  def slack_unfurl(_uri, _params), do: :skip

  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns[:current_user]

    with true <- Policy.authorize?(:error_issue_read, user, nil) || :unauthorized,
         {:ok, issue} <- Errors.fetch_issue(id) do
      events = Errors.list_events_for_issue(issue.id, limit: 10)

      {:ok,
       socket
       |> assign(:issue, issue)
       |> assign(:events, events)
       |> assign(:latest_event, List.first(events))
       |> assign(
         :page_title,
         dgettext("dashboard_errors", "%{title} · %{product}",
           title: issue.title,
           product: socket.assigns.product_name
         )
       )
       |> assign(OpenGraph.assigns(open_graph(issue)))}
    else
      :unauthorized ->
        {:ok, redirect_to_home(socket)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_errors", "Issue not found."))
         |> push_navigate(to: ~p"/errors")}
    end
  end

  def handle_event("resolve", _params, socket) do
    update_status(socket, :resolved)
  end

  def handle_event("unresolve", _params, socket) do
    update_status(socket, :unresolved)
  end

  def handle_event("ignore", _params, socket) do
    update_status(socket, :ignored)
  end

  defp update_status(socket, status) do
    case Errors.update_issue_status(socket.assigns.issue, status) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:issue, %{updated | project: socket.assigns.issue.project})
         |> put_flash(
           :info,
           dgettext("dashboard_errors", "Issue marked as %{status}.",
             status: status_label(status)
           )
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_errors", "Could not update issue status.")
         )}
    end
  end

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
      <section id="error-issue">
        <div data-part="header">
          <div data-part="title-group">
            <div data-part="breadcrumbs">
              <.link navigate={~p"/errors"}>{dgettext("dashboard_errors", "Errors")}</.link>
              <span data-part="separator">/</span>
              <span>{project_name(@issue)}</span>
            </div>
            <h1>{@issue.title}</h1>
            <p :if={@issue.culprit}>{@issue.culprit}</p>
          </div>
          <div data-part="header-actions">
            <.button
              :if={@issue.status != :resolved}
              variant="primary"
              label={dgettext("dashboard_errors", "Resolve")}
              phx-click="resolve"
            />
            <.button
              :if={@issue.status == :resolved}
              variant="secondary"
              label={dgettext("dashboard_errors", "Unresolve")}
              phx-click="unresolve"
            />
            <.button
              :if={@issue.status != :ignored}
              variant="secondary"
              label={dgettext("dashboard_errors", "Ignore")}
              phx-click="ignore"
            />
          </div>
        </div>

        <div data-part="summary">
          <.card title={dgettext("dashboard_errors", "Overview")} icon="info_circle">
            <.card_section>
              <dl data-part="stats">
                <div>
                  <dt>{dgettext("dashboard_errors", "Status")}</dt>
                  <dd>
                    <.badge
                      label={status_label(@issue.status)}
                      color={status_color(@issue.status)}
                      style="light-fill"
                    />
                  </dd>
                </div>
                <div>
                  <dt>{dgettext("dashboard_errors", "Level")}</dt>
                  <dd>
                    <.badge
                      label={level_label(@issue.level)}
                      color={level_color(@issue.level)}
                      style="light-fill"
                    />
                  </dd>
                </div>
                <div>
                  <dt>{dgettext("dashboard_errors", "Events")}</dt>
                  <dd>{@issue.event_count}</dd>
                </div>
                <div>
                  <dt>{dgettext("dashboard_errors", "Platform")}</dt>
                  <dd>{@issue.platform || "-"}</dd>
                </div>
                <div>
                  <dt>{dgettext("dashboard_errors", "First seen")}</dt>
                  <dd title={format_datetime(@issue.first_seen)}>
                    {format_date(@issue.first_seen)}
                  </dd>
                </div>
                <div>
                  <dt>{dgettext("dashboard_errors", "Last seen")}</dt>
                  <dd title={format_datetime(@issue.last_seen)}>
                    {format_date(@issue.last_seen)}
                  </dd>
                </div>
              </dl>
            </.card_section>
          </.card>
        </div>

        <.card
          :if={@latest_event}
          title={dgettext("dashboard_errors", "Latest event")}
          icon="alert_triangle"
        >
          <.card_section>
            <div data-part="event-header">
              <div data-part="event-title">
                <strong>{@latest_event.exception_type}</strong>
                <span :if={@latest_event.exception_value}>: {@latest_event.exception_value}</span>
              </div>
              <div data-part="event-meta">
                <span>{format_datetime(@latest_event.timestamp)}</span>
                <span :if={present?(@latest_event.release)}>
                  · {dgettext("dashboard_errors", "Release %{release}", release: @latest_event.release)}
                </span>
                <span :if={present?(@latest_event.environment)}>
                  · {@latest_event.environment}
                </span>
              </div>
            </div>

            <div data-part="stack-frames">
              <div
                :for={frame <- stack_frames(@latest_event)}
                data-part="frame"
                data-in-app={to_string(frame["in_app"] == true)}
              >
                <div data-part="frame-header">
                  <span data-part="function">{frame["function"] || "?"}</span>
                  <span :if={frame["filename"]} data-part="location">
                    {frame["filename"]}<span :if={frame["lineno"]}>:{frame["lineno"]}</span>
                  </span>
                </div>
                <pre :if={frame["context_line"]} data-part="context"><code>{frame["context_line"]}</code></pre>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={@events != []}
          title={dgettext("dashboard_errors", "Recent events")}
          icon="list"
        >
          <.card_section>
            <.table id="error-events-table" rows={@events}>
              <:col :let={event} label={dgettext("dashboard_errors", "Time")}>
                <.text_cell
                  label={format_datetime(event.timestamp)}
                  sublabel={format_date(event.timestamp)}
                />
              </:col>
              <:col :let={event} label={dgettext("dashboard_errors", "Level")}>
                <.badge_cell
                  label={String.capitalize(to_string(event.level))}
                  color={level_color(String.to_atom(to_string(event.level)))}
                  style="light-fill"
                />
              </:col>
              <:col :let={event} label={dgettext("dashboard_errors", "Environment")}>
                <.text_cell label={event.environment || "-"} />
              </:col>
              <:col :let={event} label={dgettext("dashboard_errors", "Release")}>
                <.text_cell label={event.release || "-"} />
              </:col>
              <:col :let={event} label={dgettext("dashboard_errors", "Message")}>
                <.text_cell
                  label={event.exception_type || "-"}
                  sublabel={event.exception_value}
                />
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="list"
                  title={dgettext("dashboard_errors", "No recent events")}
                  subtitle={dgettext("dashboard_errors", "Events for this issue will appear here.")}
                />
              </:empty_state>
            </.table>
          </.card_section>
        </.card>

        <.card
          :if={@events == [] and Errors.enabled?()}
          title={dgettext("dashboard_errors", "No recent events")}
          icon="list"
        >
          <.card_section>
            <p>
              {dgettext(
                "dashboard_errors",
                "This issue has no events in the visible window. It may have aged out of the ClickHouse retention."
              )}
            </p>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  defp redirect_to_home(socket) do
    socket
    |> put_flash(:error, dgettext("dashboard_errors", "You do not have access to errors."))
    |> push_navigate(to: ~p"/")
  end

  defp stack_frames(%{
         payload: %{"exception" => %{"values" => [%{"stacktrace" => %{"frames" => frames}} | _]}}
       })
       when is_list(frames) do
    frames
    |> Enum.reverse()
    |> Enum.take(30)
  end

  defp stack_frames(_), do: []

  defp present?(value) when is_binary(value) and byte_size(value) > 0, do: true
  defp present?(_), do: false

  defp project_name(%Issue{project: %{name: name}}), do: name
  defp project_name(_), do: "-"

  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M:%S UTC")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%H:%M:%S UTC")

  defp format_datetime(_datetime), do: "-"

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_date(%NaiveDateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
  defp format_date(_datetime), do: "-"

  defp status_label(:unresolved), do: dgettext("dashboard_errors", "Unresolved")
  defp status_label(:resolved), do: dgettext("dashboard_errors", "Resolved")
  defp status_label(:ignored), do: dgettext("dashboard_errors", "Ignored")
  defp status_label(_), do: "-"

  defp status_color(:unresolved), do: "warning"
  defp status_color(:resolved), do: "success"
  defp status_color(:ignored), do: "neutral"
  defp status_color(_), do: "neutral"

  defp level_label(:fatal), do: dgettext("dashboard_errors", "Fatal")
  defp level_label(:error), do: dgettext("dashboard_errors", "Error")
  defp level_label(:warning), do: dgettext("dashboard_errors", "Warning")
  defp level_label(:info), do: dgettext("dashboard_errors", "Info")
  defp level_label(:debug), do: dgettext("dashboard_errors", "Debug")
  defp level_label(_), do: "-"

  defp level_color(:fatal), do: "destructive"
  defp level_color(:error), do: "destructive"
  defp level_color(:warning), do: "warning"
  defp level_color(:info), do: "information"
  defp level_color(:debug), do: "neutral"
  defp level_color(_), do: "neutral"
end

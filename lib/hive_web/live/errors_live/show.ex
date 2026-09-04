defmodule HiveWeb.ErrorsLive.Show do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  import HiveWeb.PlatformIcon

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
      latest = List.first(events) || %{}
      payload = latest[:payload] || %{}

      occurrences_from = occurrences_from(issue)
      occurrences_to = DateTime.utc_now()
      occurrences = Errors.issue_occurrences(issue.id, occurrences_from, occurrences_to)

      {:ok,
       socket
       |> assign(:issue, issue)
       |> assign(:events, events)
       |> assign(:latest_event, List.first(events))
       |> assign(:latest_payload, payload)
       |> assign(:occurrences, occurrences)
       |> assign(:occurrences_from, occurrences_from)
       |> assign(:occurrences_to, occurrences_to)
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

  def handle_event("resolve", _params, socket), do: update_status(socket, :resolved)
  def handle_event("unresolve", _params, socket), do: update_status(socket, :unresolved)
  def handle_event("ignore", _params, socket), do: update_status(socket, :ignored)

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
            <h1 title={@issue.title}>{truncate_display(@issue.title, 140)}</h1>
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
              label={dgettext("dashboard_errors", "Reopen")}
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
                  <dd>
                    <.platform_icon platform={@issue.platform} label={true} />
                  </dd>
                </div>
                <div>
                  <dt>{dgettext("dashboard_errors", "First seen")}</dt>
                  <dd title={format_datetime(@issue.first_seen)}>
                    {relative_time(@issue.first_seen)}
                  </dd>
                </div>
                <div>
                  <dt>{dgettext("dashboard_errors", "Last seen")}</dt>
                  <dd title={format_datetime(@issue.last_seen)}>
                    {relative_time(@issue.last_seen)}
                  </dd>
                </div>
              </dl>
            </.card_section>
          </.card>
        </div>

        <.card
          :if={@occurrences != []}
          title={dgettext("dashboard_errors", "Occurrences")}
          icon="chart_arcs"
        >
          <.card_section>
            <div data-part="occurrences-chart">
              <.chart
                id={"occurrences-#{@issue.id}"}
                type="bar"
                series={[
                  %{
                    name: dgettext("dashboard_errors", "Events"),
                    values: Enum.map(@occurrences, fn {_bucket, count} -> count end)
                  }
                ]}
                labels={Enum.map(@occurrences, fn {bucket, _} -> format_bucket_label(bucket) end)}
                show_legend={false}
                extra_options={occurrences_chart_options()}
              />
            </div>
            <p data-part="occurrences-hint">
              {dgettext(
                "dashboard_errors",
                "Events per bucket from %{from} to %{to}. Buckets scale automatically to the window.",
                from: format_datetime(@occurrences_from),
                to: format_datetime(@occurrences_to)
              )}
            </p>
          </.card_section>
        </.card>

        <.card
          :if={@latest_event && stack_frames(@latest_payload) != []}
          title={dgettext("dashboard_errors", "Stack trace")}
          icon="alert_triangle"
        >
          <.card_section>
            <div data-part="event-header">
              <div data-part="event-title">
                <strong :if={present?(@latest_event.exception_type)}>{@latest_event.exception_type}</strong>
                <span :if={present?(@latest_event.exception_type) and present?(@latest_event.exception_value)}>:</span>
                <span :if={present?(@latest_event.exception_value)}>{@latest_event.exception_value}</span>
              </div>
              <div data-part="event-meta">
                <span>{format_datetime(@latest_event.timestamp)}</span>
                <span :if={present?(@latest_event.release)}>
                  · {dgettext("dashboard_errors", "Release %{release}",
                    release: @latest_event.release
                  )}
                </span>
                <span :if={present?(@latest_event.environment)}>
                  · {@latest_event.environment}
                </span>
              </div>
            </div>

            <div data-part="stack-frames">
              <div
                :for={frame <- stack_frames(@latest_payload)}
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
                <div :if={highlighted_frame(frame, @latest_payload)} data-part="context">
                  {Phoenix.HTML.raw(highlighted_frame(frame, @latest_payload))}
                </div>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={@latest_event && stack_frames(@latest_payload) == [] && latest_message(@latest_payload)}
          title={dgettext("dashboard_errors", "Message")}
          icon="info_circle"
        >
          <.card_section>
            <pre data-part="message-body">{latest_message(@latest_payload)}</pre>
            <p data-part="message-note">
              {dgettext(
                "dashboard_errors",
                "This event has no stack trace. The captured log did not carry crash metadata; if you're reporting it from a Sentry-compatible client, include an exception in the event payload to enable full stack-trace rendering."
              )}
            </p>
          </.card_section>
        </.card>

        <.card
          :if={tag_pairs(@issue, @latest_payload) != []}
          title={dgettext("dashboard_errors", "Tags")}
          icon="alert_hexagon"
        >
          <.card_section>
            <div data-part="context-metadata-grid" data-columns="2">
              <div :for={{key, value} <- tag_pairs(@issue, @latest_payload)} data-part="context-metadata">
                <div data-part="title">{key}</div>
                <span data-part="label">{value}</span>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={contexts(@latest_payload) != []}
          title={dgettext("dashboard_errors", "Contexts")}
          icon="stack_2"
        >
          <.card_section>
            <div data-part="contexts-grid">
              <div :for={{name, data} <- contexts(@latest_payload)} data-part="context-card">
                <div data-part="context-header">
                  <div data-part="context-icon" data-color={context_color(name)}>
                    <.icon name={context_icon(name)} />
                  </div>
                  <span data-part="context-title">{format_context_name(name)}</span>
                </div>
                <div data-part="context-metadata-grid">
                  <div :for={{k, v} <- flatten_context(data)} data-part="context-metadata">
                    <div data-part="title">{k}</div>
                    <span data-part="label">{format_context_value(v)}</span>
                  </div>
                </div>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={request_data(@latest_payload)}
          title={dgettext("dashboard_errors", "Request")}
          icon="server"
        >
          <.card_section>
            <% req = request_data(@latest_payload) %>
            <div data-part="request">
              <div :if={req["method"] || req["url"]} data-part="request-line">
                <.badge
                  label={String.upcase(req["method"] || "GET")}
                  color={http_method_color(req["method"])}
                  style="light-fill"
                  size="small"
                />
                <code>{req["url"]}</code>
              </div>

              <div :if={req["query_string"] || req["data"]} data-part="context-metadata-grid">
                <div :if={req["query_string"]} data-part="context-metadata">
                  <div data-part="title">{dgettext("dashboard_errors", "Query string")}</div>
                  <span data-part="label"><code>{req["query_string"]}</code></span>
                </div>
                <div :if={req["data"]} data-part="context-metadata">
                  <div data-part="title">{dgettext("dashboard_errors", "Body")}</div>
                  <span data-part="label">
                    <pre data-part="request-body">{format_context_value(req["data"])}</pre>
                  </span>
                </div>
              </div>

              <div :if={is_map(req["headers"]) and map_size(req["headers"]) > 0} data-part="request-headers">
                <div data-part="request-headers-title">{dgettext("dashboard_errors", "Headers")}</div>
                <div data-part="context-metadata-grid" data-columns="2">
                  <div :for={{k, v} <- Enum.sort(req["headers"])} data-part="context-metadata">
                    <div data-part="title">{k}</div>
                    <span data-part="label">{v}</span>
                  </div>
                </div>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={event_breadcrumbs(@latest_payload) != []}
          title={dgettext("dashboard_errors", "Breadcrumbs")}
          icon="list_tree"
        >
          <.card_section>
            <div data-part="timeline">
              <div
                :for={crumb <- event_breadcrumbs(@latest_payload)}
                data-part="timeline-item"
                data-level={crumb["level"] || "info"}
              >
                <div data-part="timeline-icon" data-color={crumb_color(crumb["level"])}>
                  <.icon name={crumb_icon(crumb["category"] || crumb["type"])} />
                </div>
                <div data-part="timeline-content">
                  <div data-part="timeline-header">
                    <.badge
                      label={crumb["category"] || crumb["type"] || "log"}
                      color={crumb_badge_color(crumb["level"])}
                      style="light-fill"
                      size="small"
                    />
                    <span :if={crumb["message"]} data-part="timeline-title">
                      {crumb["message"]}
                    </span>
                  </div>
                  <pre :if={is_map(crumb["data"]) and map_size(crumb["data"]) > 0} data-part="timeline-data"><code>{format_context_value(crumb["data"])}</code></pre>
                </div>
                <span data-part="timeline-time" title={format_datetime(crumb["timestamp"])}>
                  {crumb_relative_time(crumb["timestamp"])}
                </span>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={extra_pairs(@latest_payload) != []}
          title={dgettext("dashboard_errors", "Additional data")}
          icon="database"
        >
          <.card_section>
            <div data-part="context-metadata-grid">
              <div :for={{k, v} <- extra_pairs(@latest_payload)} data-part="context-metadata">
                <div data-part="title">{k}</div>
                <span data-part="label">{format_context_value(v)}</span>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={module_pairs(@latest_payload) != []}
          title={dgettext("dashboard_errors", "Modules")}
          icon="package"
        >
          <.card_section>
            <div data-part="context-metadata-grid" data-columns="2">
              <div :for={{name, version} <- module_pairs(@latest_payload)} data-part="context-metadata">
                <div data-part="title">{name}</div>
                <span data-part="label">{version}</span>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={sdk_info(@latest_payload)}
          title={dgettext("dashboard_errors", "SDK")}
          icon="devices_code"
        >
          <.card_section>
            <% sdk = sdk_info(@latest_payload) %>
            <div data-part="context-metadata-grid">
              <div :if={sdk["name"]} data-part="context-metadata">
                <div data-part="title">{dgettext("dashboard_errors", "Name")}</div>
                <span data-part="label">{sdk["name"]}</span>
              </div>
              <div :if={sdk["version"]} data-part="context-metadata">
                <div data-part="title">{dgettext("dashboard_errors", "Version")}</div>
                <span data-part="label">{sdk["version"]}</span>
              </div>
              <div :if={is_list(sdk["integrations"]) and sdk["integrations"] != []} data-part="context-metadata">
                <div data-part="title">{dgettext("dashboard_errors", "Integrations")}</div>
                <span data-part="label" data-part-inner="badge-row">
                  <.badge
                    :for={integration <- sdk["integrations"]}
                    label={integration}
                    color="focus"
                    style="light-fill"
                    size="small"
                  />
                </span>
              </div>
              <div :if={is_list(sdk["packages"]) and sdk["packages"] != []} data-part="context-metadata">
                <div data-part="title">{dgettext("dashboard_errors", "Packages")}</div>
                <span data-part="label" data-part-inner="badge-row">
                  <.badge
                    :for={pkg <- sdk["packages"]}
                    label={"#{pkg["name"]}@#{pkg["version"]}"}
                    color="neutral"
                    style="light-fill"
                    size="small"
                  />
                </span>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={@events != []}
          title={dgettext("dashboard_errors", "Recent events")}
          icon="list_tree"
        >
          <.card_section>
            <.table id="error-events-table" rows={@events}>
              <:col :let={event} label={dgettext("dashboard_errors", "Time")}>
                <.link
                  navigate={~p"/errors/#{@issue.id}/events/#{normalize_event_id(event.event_id)}"}
                  data-part="event-link"
                >
                  <.text_cell
                    label={relative_time(to_datetime(event.timestamp))}
                    {%{title: format_datetime(event.timestamp)}}
                  />
                </.link>
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
              <:empty_state>
                <.table_empty_state
                  icon="list_tree"
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
          icon="list_tree"
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

  ## Stack trace

  defp stack_frames(%{
         "exception" => %{"values" => [%{"stacktrace" => %{"frames" => frames}} | _]}
       })
       when is_list(frames) do
    frames
    |> Enum.reverse()
    |> Enum.take(30)
  end

  defp stack_frames(_), do: []

  # Returns [{line_number | nil, line_source}] with the context_line
  # first, pre_context above and post_context below.
  defp highlighted_frame(frame, payload) do
    platform = Map.get(payload, "platform")
    Hive.Errors.CodeHighlight.highlight_frame(frame, platform)
  end

  ## Tags

  defp tag_pairs(issue, payload) do
    payload_tags = as_map(payload["tags"])

    base =
      [
        {"environment", get(payload, "environment", "")},
        {"level", to_string(issue.level)},
        {"platform", get(payload, "platform", "")},
        {"release", get(payload, "release", "")},
        {"dist", get(payload, "dist", "")},
        {"server_name", get(payload, "server_name", "")},
        {"transaction", get(payload, "transaction", "")},
        {"logger", get(payload, "logger", "")}
      ]

    (base ++ Enum.to_list(payload_tags))
    |> Enum.reject(fn {_, v} -> v == "" or is_nil(v) end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.sort_by(&elem(&1, 0))
  end

  ## Contexts

  # Standard Sentry context keys we render explicitly. Anything else in
  # `contexts` still shows up under its raw name.
  @known_contexts ~w(user os runtime device browser app culture trace cloud_resource state response replay)

  defp contexts(payload) do
    map = as_map(payload["contexts"])

    user =
      case as_map(payload["user"]) do
        empty when map_size(empty) == 0 -> nil
        u -> u
      end

    map = if user, do: Map.put_new(map, "user", user), else: map

    map
    |> Enum.filter(fn {_k, v} -> is_map(v) and map_size(v) > 0 end)
    |> Enum.sort_by(fn {k, _} -> context_order(k) end)
  end

  defp context_order(name) do
    case Enum.find_index(@known_contexts, &(&1 == name)) do
      nil -> length(@known_contexts) + :erlang.phash2(name, 1000)
      idx -> idx
    end
  end

  # Acronyms Sentry Software Development Kits use as context keys.
  # Kept explicit so "os" doesn't render as "Os" — a small polish that
  # matters because these labels are the first thing a reader parses.
  @context_acronyms MapSet.new(~w(os sdk gpu cpu url http api ssl tls ip id))

  defp format_context_name(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", fn word ->
      if MapSet.member?(@context_acronyms, String.downcase(word)) do
        String.upcase(word)
      else
        String.capitalize(word)
      end
    end)
  end

  defp flatten_context(map) when is_map(map) do
    map
    |> Enum.reject(fn {k, _} -> k == "type" end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp flatten_context(_), do: []

  defp format_context_value(nil), do: "-"
  defp format_context_value(v) when is_binary(v), do: v
  defp format_context_value(v) when is_number(v) or is_boolean(v), do: to_string(v)

  # A single-map value (like `user.geo`) reads much better inline than
  # as a pretty-printed JSON block. Flatten one level and hand the
  # rest to the JSON encoder.
  defp format_context_value(map) when is_map(map) do
    if Enum.all?(map, fn {_, v} -> is_binary(v) or is_number(v) or is_boolean(v) end) do
      Enum.map_join(map, ", ", fn {k, v} -> "#{k}: #{v}" end)
    else
      Jason.encode!(map, pretty: true)
    end
  end

  defp format_context_value(v), do: Jason.encode!(v, pretty: true)

  # Sentry Software Development Kits emit a small, stable set of
  # context names. Give each one an icon and a colour so the Contexts
  # card reads as scannable cards instead of a wall of key-value
  # blocks.
  defp context_icon("user"), do: "user"
  defp context_icon("os"), do: "server"
  defp context_icon("runtime"), do: "devices_code"
  defp context_icon("device"), do: "device_desktop"
  defp context_icon("browser"), do: "devices_browser"
  defp context_icon("app"), do: "apps"
  defp context_icon("culture"), do: "language"
  defp context_icon("trace"), do: "link_icon"
  defp context_icon("cloud_resource"), do: "server"
  defp context_icon("state"), do: "database"
  defp context_icon("response"), do: "arrow_left"
  defp context_icon("replay"), do: "player_play"
  defp context_icon(_), do: "info_circle"

  defp context_color("user"), do: "information"
  defp context_color("os"), do: "neutral"
  defp context_color("runtime"), do: "focus"
  defp context_color("device"), do: "neutral"
  defp context_color("browser"), do: "information"
  defp context_color("app"), do: "success"
  defp context_color("trace"), do: "focus"
  defp context_color(_), do: "neutral"

  # Breadcrumb category → icon. Falls back to a generic log icon so
  # any custom category renders.
  defp crumb_icon("http"), do: "server"
  defp crumb_icon("http.request"), do: "server"
  defp crumb_icon("http.response"), do: "server"
  defp crumb_icon("db.query"), do: "database"
  defp crumb_icon("db"), do: "database"
  defp crumb_icon("app.lifecycle"), do: "apps"
  defp crumb_icon("navigation"), do: "link_icon"
  defp crumb_icon("ui.click"), do: "apps"
  defp crumb_icon("ui." <> _), do: "apps"
  defp crumb_icon("console"), do: "devices_code"
  defp crumb_icon("query"), do: "database"
  defp crumb_icon(_), do: "info_circle"

  defp crumb_color("error"), do: "destructive"
  defp crumb_color("fatal"), do: "destructive"
  defp crumb_color("warning"), do: "warning"
  defp crumb_color("info"), do: "information"
  defp crumb_color("debug"), do: "neutral"
  defp crumb_color(_), do: "neutral"

  defp crumb_badge_color("error"), do: "destructive"
  defp crumb_badge_color("fatal"), do: "destructive"
  defp crumb_badge_color("warning"), do: "warning"
  defp crumb_badge_color("info"), do: "information"
  defp crumb_badge_color(_), do: "neutral"

  defp crumb_relative_time(nil), do: ""
  defp crumb_relative_time(""), do: ""

  defp crumb_relative_time(ts) do
    case ts |> to_datetime() do
      %DateTime{} = dt -> relative_time(dt)
      _ -> to_string(ts)
    end
  end

  ## Request

  defp request_data(payload) do
    case as_map(payload["request"]) do
      empty when map_size(empty) == 0 -> nil
      m -> m
    end
  end

  ## Breadcrumbs

  defp event_breadcrumbs(payload) do
    case payload["breadcrumbs"] do
      %{"values" => values} when is_list(values) -> values
      values when is_list(values) -> values
      _ -> []
    end
  end

  ## Extra / additional data

  defp extra_pairs(payload) do
    payload["extra"]
    |> as_map()
    |> Enum.sort_by(&elem(&1, 0))
  end

  ## Modules

  defp module_pairs(payload) do
    payload["modules"]
    |> as_map()
    |> Enum.sort_by(&elem(&1, 0))
  end

  ## SDK

  defp sdk_info(payload) do
    case as_map(payload["sdk"]) do
      empty when map_size(empty) == 0 -> nil
      m -> m
    end
  end

  ## Helpers

  defp as_map(m) when is_map(m), do: m
  defp as_map(_), do: %{}

  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default) || default
  defp get(_, _, default), do: default

  defp present?(value) when is_binary(value) and byte_size(value) > 0, do: true
  defp present?(_), do: false

  defp truncate_display(nil, _), do: ""

  defp truncate_display(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end

  defp normalize_event_id(id) when is_binary(id), do: String.replace(id, "-", "")
  defp normalize_event_id(other), do: other |> to_string() |> String.replace("-", "")

  defp latest_message(payload) do
    case payload["message"] do
      %{"formatted" => formatted} when is_binary(formatted) and formatted != "" -> formatted
      %{"message" => message} when is_binary(message) and message != "" -> message
      msg when is_binary(msg) and msg != "" -> msg
      _ -> nil
    end
  end

  defp project_name(%Issue{project: %{name: name}}), do: name
  defp project_name(_), do: "-"

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_datetime(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_datetime(bin) when is_binary(bin), do: bin
  defp format_datetime(_), do: "-"

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> dgettext("dashboard_errors", "%{n}s ago", n: diff)
      diff < 3600 -> dgettext("dashboard_errors", "%{n}m ago", n: div(diff, 60))
      diff < 86_400 -> dgettext("dashboard_errors", "%{n}h ago", n: div(diff, 3600))
      diff < 30 * 86_400 -> dgettext("dashboard_errors", "%{n}d ago", n: div(diff, 86_400))
      diff < 365 * 86_400 -> dgettext("dashboard_errors", "%{n}mo ago", n: div(diff, 30 * 86_400))
      true -> dgettext("dashboard_errors", "%{n}y ago", n: div(diff, 365 * 86_400))
    end
  end

  defp relative_time(_), do: "-"

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp to_datetime(bin) when is_binary(bin) do
    case DateTime.from_iso8601(bin) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp to_datetime(_), do: nil

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

  # Pick the window for the occurrences chart. Prefer the interval
  # between first_seen and now (bounded to 30 days) so short-lived
  # issues aren't dwarfed by empty older buckets.
  defp occurrences_from(%{first_seen: %DateTime{} = first}) do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)
    if DateTime.compare(first, thirty_days_ago) == :lt, do: thirty_days_ago, else: first
  end

  defp occurrences_from(_), do: DateTime.add(DateTime.utc_now(), -30, :day)

  defp format_bucket_label(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_bucket_label(other), do: to_string(other)

  defp occurrences_chart_options do
    %{
      grid: %{left: 30, right: 10, top: 10, bottom: 30, containLabel: true},
      xAxis: %{
        show: true,
        type: "category",
        axisLabel: %{formatter: "fn:firstAndLastDate", color: "#8B8D97", fontSize: 10}
      },
      yAxis: %{show: true, splitLine: %{lineStyle: %{opacity: 0.15}}},
      tooltip: %{show: true, trigger: "axis", dateFormat: "minute"},
      legend: %{show: false}
    }
  end

  defp http_method_color("GET"), do: "information"
  defp http_method_color("POST"), do: "success"
  defp http_method_color("PUT"), do: "warning"
  defp http_method_color("PATCH"), do: "warning"
  defp http_method_color("DELETE"), do: "destructive"

  defp http_method_color(method) when is_binary(method),
    do: http_method_color(String.upcase(method))

  defp http_method_color(_), do: "neutral"

  defp level_color(:fatal), do: "destructive"
  defp level_color(:error), do: "destructive"
  defp level_color(:warning), do: "warning"
  defp level_color(:info), do: "information"
  defp level_color(:debug), do: "neutral"
  defp level_color(_), do: "neutral"
end

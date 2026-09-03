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
      latest = List.first(events) || %{}
      payload = latest[:payload] || %{}

      {:ok,
       socket
       |> assign(:issue, issue)
       |> assign(:events, events)
       |> assign(:latest_event, List.first(events))
       |> assign(:latest_payload, payload)
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
                  <dd>{platform_label(@issue.platform)}</dd>
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
                  <span data-part="function">{frame["function"] || "?"}</span>
                  <span data-part="module" :if={frame["module"]}>{frame["module"]}</span>
                  <span :if={frame["filename"]} data-part="location">
                    {frame["filename"]}<span :if={frame["lineno"]}>:{frame["lineno"]}</span>
                  </span>
                </div>
                <pre :if={source_context(frame) != []} data-part="context"><code><span :for={line <- source_context(frame)} data-part={context_line_part(line, frame)}>{format_context_line(line)}</span></code></pre>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          :if={tag_pairs(@issue, @latest_payload) != []}
          title={dgettext("dashboard_errors", "Tags")}
          icon="alert_hexagon"
        >
          <.card_section>
            <dl data-part="tags">
              <div :for={{key, value} <- tag_pairs(@issue, @latest_payload)} data-part="tag-pair">
                <dt>{key}</dt>
                <dd>{value}</dd>
              </div>
            </dl>
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
                <div data-part="context-title">{format_context_name(name)}</div>
                <dl>
                  <div :for={{k, v} <- flatten_context(data)} data-part="context-row">
                    <dt>{k}</dt>
                    <dd>{format_context_value(v)}</dd>
                  </div>
                </dl>
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
            <dl data-part="request">
              <div :if={req["method"] || req["url"]} data-part="request-line">
                <strong>{req["method"] || "GET"}</strong>
                <span>{req["url"]}</span>
              </div>
              <div :if={req["query_string"]} data-part="request-field">
                <dt>{dgettext("dashboard_errors", "Query string")}</dt>
                <dd><code>{req["query_string"]}</code></dd>
              </div>
              <div :if={is_map(req["headers"]) and map_size(req["headers"]) > 0} data-part="request-field">
                <dt>{dgettext("dashboard_errors", "Headers")}</dt>
                <dd>
                  <dl data-part="kv-list">
                    <div :for={{k, v} <- Enum.sort(req["headers"])} data-part="kv-row">
                      <dt>{k}</dt>
                      <dd>{v}</dd>
                    </div>
                  </dl>
                </dd>
              </div>
              <div :if={req["data"]} data-part="request-field">
                <dt>{dgettext("dashboard_errors", "Body")}</dt>
                <dd><pre>{format_context_value(req["data"])}</pre></dd>
              </div>
            </dl>
          </.card_section>
        </.card>

        <.card
          :if={event_breadcrumbs(@latest_payload) != []}
          title={dgettext("dashboard_errors", "Breadcrumbs")}
          icon="list_tree"
        >
          <.card_section>
            <ol data-part="breadcrumbs-list">
              <li :for={crumb <- event_breadcrumbs(@latest_payload)} data-part="crumb" data-level={crumb["level"] || "info"}>
                <div data-part="crumb-header">
                  <span data-part="crumb-time">{format_datetime(crumb["timestamp"])}</span>
                  <span data-part="crumb-category">{crumb["category"] || crumb["type"] || "log"}</span>
                  <span data-part="crumb-level">{crumb["level"] || "info"}</span>
                </div>
                <div :if={crumb["message"]} data-part="crumb-message">{crumb["message"]}</div>
                <pre :if={is_map(crumb["data"]) and map_size(crumb["data"]) > 0} data-part="crumb-data"><code>{format_context_value(crumb["data"])}</code></pre>
              </li>
            </ol>
          </.card_section>
        </.card>

        <.card
          :if={extra_pairs(@latest_payload) != []}
          title={dgettext("dashboard_errors", "Additional data")}
          icon="database"
        >
          <.card_section>
            <dl data-part="kv-list">
              <div :for={{k, v} <- extra_pairs(@latest_payload)} data-part="kv-row">
                <dt>{k}</dt>
                <dd><pre>{format_context_value(v)}</pre></dd>
              </div>
            </dl>
          </.card_section>
        </.card>

        <.card
          :if={module_pairs(@latest_payload) != []}
          title={dgettext("dashboard_errors", "Modules")}
          icon="package"
        >
          <.card_section>
            <dl data-part="kv-list">
              <div :for={{name, version} <- module_pairs(@latest_payload)} data-part="kv-row">
                <dt>{name}</dt>
                <dd>{version}</dd>
              </div>
            </dl>
          </.card_section>
        </.card>

        <.card
          :if={sdk_info(@latest_payload)}
          title={dgettext("dashboard_errors", "SDK")}
          icon="devices_code"
        >
          <.card_section>
            <% sdk = sdk_info(@latest_payload) %>
            <dl data-part="kv-list">
              <div :if={sdk["name"]} data-part="kv-row">
                <dt>{dgettext("dashboard_errors", "Name")}</dt>
                <dd>{sdk["name"]}</dd>
              </div>
              <div :if={sdk["version"]} data-part="kv-row">
                <dt>{dgettext("dashboard_errors", "Version")}</dt>
                <dd>{sdk["version"]}</dd>
              </div>
              <div :if={is_list(sdk["integrations"]) and sdk["integrations"] != []} data-part="kv-row">
                <dt>{dgettext("dashboard_errors", "Integrations")}</dt>
                <dd>{Enum.join(sdk["integrations"], ", ")}</dd>
              </div>
              <div :if={is_list(sdk["packages"]) and sdk["packages"] != []} data-part="kv-row">
                <dt>{dgettext("dashboard_errors", "Packages")}</dt>
                <dd>
                  <ul data-part="package-list">
                    <li :for={pkg <- sdk["packages"]}>{pkg["name"]}@{pkg["version"]}</li>
                  </ul>
                </dd>
              </div>
            </dl>
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
                <.text_cell label={event.exception_type || "-"} sublabel={event.exception_value} />
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

  defp stack_frames(%{"exception" => %{"values" => [%{"stacktrace" => %{"frames" => frames}} | _]}})
       when is_list(frames) do
    frames
    |> Enum.reverse()
    |> Enum.take(30)
  end

  defp stack_frames(_), do: []

  # Returns [{line_number | nil, line_source}] with the context_line
  # first, pre_context above and post_context below.
  defp source_context(frame) do
    pre = list(frame["pre_context"])
    ctx = frame["context_line"]
    post = list(frame["post_context"])

    if ctx == nil and pre == [] and post == [] do
      []
    else
      base_line = frame["lineno"] || 0
      pre_count = length(pre)

      pre_with_line = Enum.with_index(pre, fn line, i -> {base_line - pre_count + i, line, :pre} end)
      current = if ctx, do: [{base_line, ctx, :current}], else: []

      post_with_line =
        Enum.with_index(post, fn line, i -> {base_line + i + 1, line, :post} end)

      pre_with_line ++ current ++ post_with_line
    end
  end

  defp context_line_part({_, _, :current}, _), do: "context-current"
  defp context_line_part(_, _), do: "context-line"

  defp format_context_line({line, source, _}) do
    prefix = if line, do: String.pad_leading("#{line}", 4), else: "    "
    "#{prefix}  #{source}\n"
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

  defp format_context_name(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
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
  defp format_context_value(v), do: Jason.encode!(v, pretty: true)

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

  defp list(l) when is_list(l), do: l
  defp list(_), do: []

  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default) || default
  defp get(_, _, default), do: default

  defp present?(value) when is_binary(value) and byte_size(value) > 0, do: true
  defp present?(_), do: false

  defp project_name(%Issue{project: %{name: name}}), do: name
  defp project_name(_), do: "-"

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_datetime(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_datetime(bin) when is_binary(bin), do: bin
  defp format_datetime(_), do: "-"

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_date(_), do: "-"

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

  # Sentry Software Development Kits transmit a small set of `platform`
  # identifiers on every event. Map them to friendly labels so the UI
  # doesn't read like debug output. Unknown platforms fall through as
  # a capitalized version of the identifier.
  defp platform_label(nil), do: "-"
  defp platform_label(""), do: "-"
  defp platform_label("elixir"), do: "Elixir"
  defp platform_label("javascript"), do: "JavaScript"
  defp platform_label("node"), do: "Node.js"
  defp platform_label("python"), do: "Python"
  defp platform_label("ruby"), do: "Ruby"
  defp platform_label("java"), do: "Java"
  defp platform_label("csharp"), do: "C#"
  defp platform_label("go"), do: "Go"
  defp platform_label("php"), do: "PHP"
  defp platform_label("perl"), do: "Perl"
  defp platform_label("rust"), do: "Rust"
  defp platform_label("swift"), do: "Swift"
  defp platform_label("cocoa"), do: "Cocoa"
  defp platform_label("objc"), do: "Objective-C"
  defp platform_label("kotlin"), do: "Kotlin"
  defp platform_label("dart"), do: "Dart"
  defp platform_label("native"), do: "Native"
  defp platform_label("other"), do: "Other"
  defp platform_label(other) when is_binary(other), do: String.capitalize(other)
  defp platform_label(other), do: to_string(other)

  defp level_color(:fatal), do: "destructive"
  defp level_color(:error), do: "destructive"
  defp level_color(:warning), do: "warning"
  defp level_color(:info), do: "information"
  defp level_color(:debug), do: "neutral"
  defp level_color(_), do: "neutral"
end

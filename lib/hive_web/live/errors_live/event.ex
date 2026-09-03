defmodule HiveWeb.ErrorsLive.Event do
  @moduledoc """
  Detail page for a single event captured under an issue. Renders the
  same panels as the issue detail page (Tags, Contexts, Request,
  Breadcrumbs, Additional data, Modules, SDK, Stack trace) but scoped
  to the specific event referenced in the URL rather than the latest.
  """

  use HiveWeb, :live_view
  use Noora

  import HiveWeb.PlatformIcon

  alias Hive.Errors
  alias Hive.Errors.Issue
  alias Hive.Errors.Policy
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def slack_unfurl(_uri, _params), do: :skip

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
           title: dgettext("dashboard_errors", "Event %{short}", short: short_id(event[:event_id] || event_id))
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
              <.link navigate={~p"/errors/#{@issue.id}"}>{truncate_display(@issue.title, 60)}</.link>
              <span data-part="separator">/</span>
              <span>{dgettext("dashboard_errors", "Event %{short}", short: short_id(@event.event_id))}</span>
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
          :if={stack_frames(@payload) == [] && latest_message(@payload)}
          title={dgettext("dashboard_errors", "Message")}
          icon="info_circle"
        >
          <.card_section>
            <pre data-part="message-body">{latest_message(@payload)}</pre>
          </.card_section>
        </.card>

        <.card
          :if={tag_pairs(@issue, @payload) != []}
          title={dgettext("dashboard_errors", "Tags")}
          icon="alert_hexagon"
        >
          <.card_section>
            <dl data-part="tags">
              <div :for={{key, value} <- tag_pairs(@issue, @payload)} data-part="tag-pair">
                <dt>{key}</dt>
                <dd>{value}</dd>
              </div>
            </dl>
          </.card_section>
        </.card>

        <.card
          :if={contexts(@payload) != []}
          title={dgettext("dashboard_errors", "Contexts")}
          icon="stack_2"
        >
          <.card_section>
            <div data-part="contexts-grid">
              <div :for={{name, data} <- contexts(@payload)} data-part="context-card">
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
          :if={request_data(@payload)}
          title={dgettext("dashboard_errors", "Request")}
          icon="server"
        >
          <.card_section>
            <% req = request_data(@payload) %>
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
          :if={event_breadcrumbs(@payload) != []}
          title={dgettext("dashboard_errors", "Breadcrumbs")}
          icon="list_tree"
        >
          <.card_section>
            <ol data-part="breadcrumbs-list">
              <li :for={crumb <- event_breadcrumbs(@payload)} data-part="crumb" data-level={crumb["level"] || "info"}>
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
          :if={extra_pairs(@payload) != []}
          title={dgettext("dashboard_errors", "Additional data")}
          icon="database"
        >
          <.card_section>
            <dl data-part="kv-list">
              <div :for={{k, v} <- extra_pairs(@payload)} data-part="kv-row">
                <dt>{k}</dt>
                <dd><pre>{format_context_value(v)}</pre></dd>
              </div>
            </dl>
          </.card_section>
        </.card>

        <.card
          :if={module_pairs(@payload) != []}
          title={dgettext("dashboard_errors", "Modules")}
          icon="package"
        >
          <.card_section>
            <dl data-part="kv-list">
              <div :for={{name, version} <- module_pairs(@payload)} data-part="kv-row">
                <dt>{name}</dt>
                <dd>{version}</dd>
              </div>
            </dl>
          </.card_section>
        </.card>

        <.card
          :if={sdk_info(@payload)}
          title={dgettext("dashboard_errors", "SDK")}
          icon="devices_code"
        >
          <.card_section>
            <% sdk = sdk_info(@payload) %>
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
            </dl>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  ## Helpers (mirrored from HiveWeb.ErrorsLive.Show; kept inline for now)

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

  defp stack_frames(%{"exception" => %{"values" => [%{"stacktrace" => %{"frames" => frames}} | _]}})
       when is_list(frames) do
    frames |> Enum.reverse() |> Enum.take(30)
  end

  defp stack_frames(_), do: []

  defp source_context(frame) do
    pre = list(frame["pre_context"])
    ctx = frame["context_line"]
    post = list(frame["post_context"])

    if ctx == nil and pre == [] and post == [] do
      []
    else
      base_line = frame["lineno"] || 0
      pre_count = length(pre)

      pre_lines =
        Enum.with_index(pre, fn line, i -> {base_line - pre_count + i, line, :pre} end)

      current = if ctx, do: [{base_line, ctx, :current}], else: []

      post_lines = Enum.with_index(post, fn line, i -> {base_line + i + 1, line, :post} end)

      pre_lines ++ current ++ post_lines
    end
  end

  defp context_line_part({_, _, :current}, _), do: "context-current"
  defp context_line_part(_, _), do: "context-line"

  defp format_context_line({line, source, _}) do
    prefix = if line, do: String.pad_leading("#{line}", 4), else: "    "
    "#{prefix}  #{source}\n"
  end

  defp tag_pairs(issue, payload) do
    payload_tags = as_map(payload["tags"])

    base = [
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

  defp request_data(payload) do
    case as_map(payload["request"]) do
      empty when map_size(empty) == 0 -> nil
      m -> m
    end
  end

  defp event_breadcrumbs(payload) do
    case payload["breadcrumbs"] do
      %{"values" => values} when is_list(values) -> values
      values when is_list(values) -> values
      _ -> []
    end
  end

  defp extra_pairs(payload) do
    payload["extra"] |> as_map() |> Enum.sort_by(&elem(&1, 0))
  end

  defp module_pairs(payload) do
    payload["modules"] |> as_map() |> Enum.sort_by(&elem(&1, 0))
  end

  defp sdk_info(payload) do
    case as_map(payload["sdk"]) do
      empty when map_size(empty) == 0 -> nil
      m -> m
    end
  end

  defp latest_message(payload) do
    case payload["message"] do
      %{"formatted" => formatted} when is_binary(formatted) and formatted != "" -> formatted
      %{"message" => message} when is_binary(message) and message != "" -> message
      msg when is_binary(msg) and msg != "" -> msg
      _ -> nil
    end
  end

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

  defp truncate_display(nil, _), do: ""

  defp truncate_display(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end
end

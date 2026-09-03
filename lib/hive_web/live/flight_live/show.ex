defmodule HiveWeb.FlightLive.Show do
  @moduledoc false

  use HiveWeb, :live_view
  use Noora

  @behaviour Hive.Slack.Unfurl

  alias Hive.Flights
  alias Hive.Slack.Unfurl.BlockKit
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph(flight) do
    %{
      description: flight_description(flight),
      section_label: dgettext("dashboard_flights", "Flight"),
      highlights: [
        Flights.objective_label(flight.objective),
        Flights.status_label(flight.status),
        flight.repository_full_name,
        forage_title(flight)
      ],
      id: "flight-#{flight.id}",
      path: Flights.path(flight),
      title: Flights.title(flight)
    }
  end

  @impl Hive.Slack.Unfurl
  def slack_unfurl(uri, _params) do
    BlockKit.generic(uri, %{
      description:
        dgettext(
          "dashboard_flights",
          "Sign in to Hive to inspect this durable agent execution."
        ),
      highlights: [
        dgettext("dashboard_flights", "Execution history"),
        dgettext("dashboard_flights", "Product signal context"),
        dgettext("dashboard_flights", "Continuation details")
      ],
      section_label: dgettext("dashboard_flights", "Flights"),
      title: dgettext("dashboard_flights", "Hive Flight")
    })
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Flights.get_flight_for_user(id, socket.assigns[:current_user]) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_flights", "Flight not found."))
         |> push_navigate(to: ~p"/flights")}

      flight ->
        {:ok,
         socket
         |> assign(:flight, flight)
         |> assign(
           :page_title,
           dgettext("dashboard_flights", "%{title} · %{product}",
             title: Flights.title(flight),
             product: socket.assigns.product_name
           )
         )
         |> assign(OpenGraph.assigns(open_graph(flight)))}
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
      <section id="flight-show">
        <div data-part="header">
          <div data-part="title-group">
            <div data-part="eyebrow">
              <.badge
                label={Flights.status_label(@flight.status)}
                color={Flights.status_color(@flight.status)}
                style="light-fill"
              />
              <span>{@flight.repository_full_name}</span>
            </div>
            <h1>{Flights.title(@flight)}</h1>
            <p>{flight_description(@flight)}</p>
          </div>
          <div data-part="header-actions">
            <.link
              :if={Flights.forage_item_path(@flight.forage_item)}
              navigate={Flights.forage_item_path(@flight.forage_item)}
            >
              <.button
                label={dgettext("dashboard_flights", "Open Forage item")}
                variant="secondary"
                size="small"
              >
                <:icon_right><.icon name="external_link" /></:icon_right>
              </.button>
            </.link>
            <.button
              :if={pull_request_url(@flight)}
              label={dgettext("dashboard_flights", "View pull request")}
              variant="secondary"
              size="small"
              href={pull_request_url(@flight)}
              target="_blank"
              rel="noreferrer noopener"
            >
              <:icon_right><.icon name="external_link" /></:icon_right>
            </.button>
          </div>
        </div>

        <.card title={dgettext("dashboard_flights", "Execution")} icon="player_play">
          <.card_section>
            <div data-part="metadata-grid">
              <.metadata label={dgettext("dashboard_flights", "Flight identifier")} value={@flight.id} />
              <.metadata label={dgettext("dashboard_flights", "Objective")} value={Flights.objective_label(@flight.objective)} />
              <.metadata label={dgettext("dashboard_flights", "Objective outcome")} value={objective_outcome(@flight)} />
              <.metadata label={dgettext("dashboard_flights", "Runner")} value={runner_label(@flight.runner)} />
              <.metadata label={dgettext("dashboard_flights", "Sandbox identifier")} value={@flight.runner_id || "-"} />
              <.metadata label={dgettext("dashboard_flights", "Requested by")} value={requester(@flight)} />
              <.metadata label={dgettext("dashboard_flights", "Triggered from")} value={trigger_label(@flight)} />
              <.metadata label={dgettext("dashboard_flights", "Started")} value={format_datetime(@flight.started_at)} />
              <.metadata label={dgettext("dashboard_flights", "Completed")} value={format_datetime(@flight.completed_at)} />
              <.metadata label={dgettext("dashboard_flights", "Base branch")} value={source_value(@flight, "base_branch")} />
              <.metadata label={dgettext("dashboard_flights", "Base revision")} value={source_value(@flight, "base_revision")} />
            </div>
          </.card_section>
        </.card>

        <.card
          :if={@flight.result || @flight.error}
          title={dgettext("dashboard_flights", "Outcome")}
          icon="circle_check"
        >
          <.card_section>
            <div data-part="outcome">
              <p :if={result_summary(@flight)}>{result_summary(@flight)}</p>
              <div :if={result_root_cause(@flight)} data-part="finding">
                <span>{dgettext("dashboard_flights", "Root cause")}</span>
                <p>{result_root_cause(@flight)}</p>
              </div>
              <div :if={validation(@flight) != []} data-part="validation">
                <span>{dgettext("dashboard_flights", "Validation")}</span>
                <ul>
                  <li :for={check <- validation(@flight)}><code>{check}</code></li>
                </ul>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card title={dgettext("dashboard_flights", "Continue locally")} icon="devices_code">
          <.card_section>
            <div data-part="continuation">
              <p>
                {dgettext(
                  "dashboard_flights",
                  "Check out the recorded revision, then ask your local Hive client for this Flight. The response includes the portable session messages and outcome."
                )}
              </p>
              <div data-part="commands">
                <code>git clone https://github.com/{@flight.repository_full_name}.git</code>
                <code>git checkout {checkout_revision(@flight)}</code>
                <code>{mcp_command(@flight)}</code>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card title={dgettext("dashboard_flights", "Agent session")} icon="message_circle">
          <.card_section>
            <div :if={session_messages(@flight) == []} data-part="empty-session">
              <div data-part="empty-icon"><.icon name="message_circle" /></div>
              <strong>{dgettext("dashboard_flights", "No session was captured")}</strong>
              <p>
                {dgettext(
                  "dashboard_flights",
                  "Flights created before session capture or failures before the agent starts do not have a transcript."
                )}
              </p>
            </div>
            <div :if={session_messages(@flight) != []} data-part="session">
              <article :for={{message, index} <- Enum.with_index(session_messages(@flight))} data-part="message">
                <div data-part="message-header">
                  <.badge
                    label={message_role(message)}
                    color={message_color(message)}
                    style="light-fill"
                  />
                  <time :if={message["timestamp"]}>{format_timestamp(message["timestamp"])}</time>
                </div>
                <pre :if={message_text(message) != ""} id={"flight-message-#{index}"}>{message_text(message)}</pre>
                <div :if={tool_calls(message) != []} data-part="tool-calls">
                  <div :for={tool <- tool_calls(message)} data-part="tool-call">
                    <span><.icon name="settings" /> {tool["name"]}</span>
                    <pre>{format_arguments(tool["arguments"])}</pre>
                  </div>
                </div>
              </article>
            </div>
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp metadata(assigns) do
    ~H"""
    <div data-part="metadata">
      <span>{@label}</span>
      <strong>{@value}</strong>
    </div>
    """
  end

  defp flight_description(%{result: %{"summary" => summary}}) when is_binary(summary), do: summary
  defp flight_description(%{error: error}) when is_binary(error), do: error

  defp flight_description(%{status: :running}),
    do: dgettext("dashboard_flights", "The agent is working in its sandbox.")

  defp flight_description(%{status: :queued}),
    do: dgettext("dashboard_flights", "Waiting for an available sandbox.")

  defp flight_description(_flight),
    do: dgettext("dashboard_flights", "Durable agent execution and continuation context.")

  defp forage_title(%{forage_item: %{title: title}}), do: title
  defp forage_title(_flight), do: dgettext("dashboard_flights", "Forage item unavailable")

  defp result_summary(%{error: error}) when is_binary(error), do: error
  defp result_summary(%{result: %{"summary" => summary}}), do: summary
  defp result_summary(_flight), do: nil

  defp result_root_cause(%{result: %{"root_cause" => root_cause}}), do: root_cause
  defp result_root_cause(_flight), do: nil

  defp validation(%{result: %{"validation" => validation}}) when is_list(validation),
    do: validation

  defp validation(_flight), do: []

  defp pull_request_url(%{result: %{"url" => url}}) when is_binary(url), do: url
  defp pull_request_url(_flight), do: nil

  defp session_messages(%{session: %{"messages" => messages}}) when is_list(messages),
    do: messages

  defp session_messages(_flight), do: []

  defp message_role(%{"role" => "user"}), do: dgettext("dashboard_flights", "User")
  defp message_role(%{"role" => "assistant"}), do: dgettext("dashboard_flights", "Agent")
  defp message_role(%{"role" => "tool_result"}), do: dgettext("dashboard_flights", "Tool result")
  defp message_role(_message), do: dgettext("dashboard_flights", "Message")

  defp message_color(%{"role" => "user"}), do: "information"
  defp message_color(%{"role" => "assistant"}), do: "focus"
  defp message_color(%{"role" => "tool_result"}), do: "neutral"
  defp message_color(_message), do: "neutral"

  defp message_text(%{"content" => content}) when is_binary(content), do: content

  defp message_text(%{"content" => blocks}) when is_list(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("\n", &(&1["text"] || ""))
  end

  defp message_text(%{"content" => content}) when is_map(content), do: JSON.encode!(content)
  defp message_text(_message), do: ""

  defp tool_calls(%{"content" => blocks}) when is_list(blocks),
    do: Enum.filter(blocks, &(&1["type"] == "tool_call"))

  defp tool_calls(_message), do: []

  defp format_arguments(arguments) when is_map(arguments), do: JSON.encode!(arguments)
  defp format_arguments(arguments), do: to_string(arguments || "")

  defp source_value(%{session: %{"source" => source}}, key), do: source[key] || "-"
  defp source_value(_flight, _key), do: "-"

  defp checkout_revision(%{result: %{"branch" => branch}}) when is_binary(branch), do: branch
  defp checkout_revision(flight), do: source_value(flight, "base_revision")

  defp mcp_command(flight), do: ~s(get_flight {"id":"#{flight.id}"})

  defp requester(%{requested_by: %{name: name}}) when is_binary(name) and name != "", do: name
  defp requester(%{requested_by: %{email: email}}) when is_binary(email), do: email
  defp requester(_flight), do: dgettext("dashboard_flights", "System")

  defp objective_outcome(%{objective_outcome: nil}), do: "-"

  defp objective_outcome(%{objective_outcome: outcome}),
    do: Flights.objective_outcome_label(outcome)

  defp trigger_label(%{trigger: %{"source" => "slack"}}), do: "Slack"
  defp trigger_label(%{trigger: %{"source" => "mcp"}}), do: "Model Context Protocol"
  defp trigger_label(%{trigger: %{"source" => "dashboard"}}), do: "Dashboard"
  defp trigger_label(_flight), do: "-"

  defp runner_label(runner) when is_binary(runner) do
    runner
    |> String.replace(["_", "-"], " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp runner_label(_runner), do: "-"

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%b %d, %Y · %H:%M UTC")

  defp format_datetime(_datetime), do: "-"

  defp format_timestamp(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%H:%M:%S UTC")
      _error -> timestamp
    end
  end
end

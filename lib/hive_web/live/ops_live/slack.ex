defmodule HiveWeb.OpsLive.Slack do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Ops.Policy
  alias Hive.Slack
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description: "Connect Slack workspaces to Hive.",
      section_label: "Ops",
      highlights: ["Slack OAuth", "Workspace installs", "Message shortcuts"],
      id: "ops-slack",
      path: "/ops/slack",
      title: "Slack"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Log in to manage Slack workspaces.")
         |> redirect(to: ~p"/login?return_to=/ops/slack")}

      not Policy.authorize?(:slack_workspace_manage, user, nil) ->
        {:ok,
         socket
         |> put_flash(:error, "Only instance admins can manage Slack workspaces.")
         |> push_navigate(to: ~p"/")}

      true ->
        {:ok,
         socket
         |> assign(:page_title, "Slack · #{socket.assigns.product_name}")
         |> assign(OpenGraph.assigns(open_graph()))
         |> assign(:slack_enabled?, Slack.enabled?())
         |> assign(:notification_routes, Slack.notification_routes())
         |> assign(:installations, Slack.list_installations())}
    end
  end

  @impl true
  def handle_event("save_notification_routes", %{"id" => id, "installation" => params}, socket) do
    case Enum.find(socket.assigns.installations, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Slack workspace not found.")}

      installation ->
        case Slack.update_notification_routes(installation, params) do
          {:ok, _installation} ->
            {:noreply,
             socket
             |> put_flash(:info, "Slack notification routes updated.")
             |> push_event("close-modal", %{id: "slack-routes-modal-#{installation.id}"})
             |> assign(:installations, Slack.list_installations())}

          {:error, _changeset} ->
            {:noreply,
             put_flash(socket, :error, "Slack notification routes could not be updated.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.ops
      flash={@flash}
      product_name={@product_name}
      user_name={@user_name}
      user_email={@user_email}
      avatar_color={@avatar_color}
      signed_in?={@signed_in?}
      csrf_token={@csrf_token}
      current_path={@current_path}
    >
      <section id="ops-slack">
        <div data-part="page-header">
          <div data-part="title-group">
            <h1>Slack</h1>
            <p>
              Connect Slack workspaces to Hive. Once installed, the bot can reply in threads
              and capture messages as feature requests.
            </p>
          </div>
        </div>

        <.card icon="brand_slack" title="Workspaces" data-part="workspaces-card">
          <:actions :if={@slack_enabled?}>
            <.button
              label={if @installations == [], do: "Connect workspace", else: "Connect another workspace"}
              href={~p"/slack/install"}
              variant="secondary"
              size="small"
            />
          </:actions>
          <.card_section data-part="installations-section">
            <div data-part="workspaces-table">
              <.table
                id="slack-workspaces-table"
                rows={if @slack_enabled?, do: @installations, else: []}
                row_key={fn installation -> "slack-installation-#{installation.id}" end}
              >
                <:col :let={installation} label="Workspace">
                  <.text_and_description_cell
                    icon="brand_slack"
                    label={installation.team_name || installation.team_id}
                    description={workspace_description(installation)}
                  />
                </:col>
                <:col :let={installation} label="Status">
                  <.badge_cell
                    :if={is_nil(installation.disconnected_at)}
                    label="Connected"
                    color="success"
                    style="light-fill"
                  />
                  <.badge_cell
                    :if={installation.disconnected_at}
                    label="Disconnected"
                    color="neutral"
                    style="light-fill"
                  />
                </:col>
                <:col :let={installation} label="Installed">
                  <.text_cell
                    label={installed_by_label(installation)}
                    sublabel={installed_on_label(installation)}
                  />
                </:col>
                <:col :let={installation} label="Channel">
                  <.text_cell
                    label={notification_channel_label(installation, @notification_routes)}
                    sublabel={notification_channel_sublabel(installation, @notification_routes)}
                  />
                </:col>
                <:col :let={installation} label="Notifications">
                  <.text_cell
                    label={notification_summary_label(installation, @notification_routes)}
                    sublabel={notification_summary_sublabel(installation, @notification_routes)}
                  />
                </:col>
                <:col :let={installation} label="">
                  <.button_cell>
                    <:button :if={is_nil(installation.disconnected_at)}>
                      <.modal
                        id={"slack-routes-modal-#{installation.id}"}
                        title={"Edit #{installation.team_name || installation.team_id} routes"}
                        description="Route Hive notifications to Slack channel identifiers."
                        header_type="icon"
                        header_size="large"
                      >
                        <:trigger :let={attrs}>
                          <.button
                            label="Edit routes"
                            variant="secondary"
                            size="small"
                            icon_only={true}
                            title="Edit routes"
                            aria-label="Edit routes"
                            {attrs}
                          >
                            <.pencil />
                          </.button>
                        </:trigger>
                        <:header_icon>
                          <.icon name="brand_slack" />
                        </:header_icon>

                        <.form
                          id={"slack-routes-form-#{installation.id}"}
                          for={%{}}
                          as={:installation}
                          phx-submit="save_notification_routes"
                          phx-value-id={installation.id}
                          data-part="notification-routes-form"
                        >
                          <div data-part="notification-route-fields">
                            <div
                              :for={route <- @notification_routes}
                              data-part="notification-route-field"
                            >
                              <div data-part="notification-route-copy">
                                <span>{route.label}</span>
                                <small>{route.description}</small>
                                <small>{notification_event_labels(route)}</small>
                              </div>
                              <.text_input
                                id={"notification-route-#{installation.id}-#{route.object_type}"}
                                name={"installation[notification_routes][#{route.object_type}][slack_channel_id]"}
                                value={notification_channel_value(installation, route)}
                                label="Slack channel"
                                placeholder="C0123456789"
                                show_suffix={false}
                              />
                            </div>
                          </div>
                        </.form>

                        <:footer>
                          <.modal_footer>
                            <:action>
                              <.button
                                label="Save routes"
                                variant="primary"
                                size="medium"
                                type="submit"
                                form={"slack-routes-form-#{installation.id}"}
                              />
                            </:action>
                          </.modal_footer>
                        </:footer>
                      </.modal>
                    </:button>
                    <:button :if={is_nil(installation.disconnected_at)}>
                      <form
                        method="post"
                        action={~p"/slack/installations/#{installation.id}/disconnect"}
                        data-part="workspace-actions"
                      >
                        <input type="hidden" name="_csrf_token" value={@csrf_token} />
                        <.button
                          label="Disconnect"
                          variant="destructive"
                          size="small"
                          icon_only={true}
                          title="Disconnect workspace"
                          aria-label="Disconnect workspace"
                        >
                          <.trash />
                        </.button>
                      </form>
                    </:button>
                  </.button_cell>
                </:col>
                <:empty_state>
                  <.table_empty_state
                    icon="brand_slack"
                    title={slack_empty_title(@slack_enabled?)}
                    subtitle={slack_empty_subtitle(@slack_enabled?)}
                  />
                </:empty_state>
              </.table>
            </div>
          </.card_section>
        </.card>
      </section>
    </Layouts.ops>
    """
  end

  defp notification_channel_value(installation, route) do
    installation
    |> Slack.notification_route_for(route.object_type)
    |> Map.get(:slack_channel_id, "")
  end

  defp workspace_description(installation) do
    case installation.team_id do
      team_id when is_binary(team_id) and team_id != "" -> "Workspace #{team_id}"
      _team_id -> "Workspace"
    end
  end

  defp installed_by_label(%{installed_by_user: %{email: email}}) when is_binary(email), do: email
  defp installed_by_label(_installation), do: "Unknown installer"

  defp installed_on_label(%{installed_at: %DateTime{} = installed_at}) do
    "Installed on #{Calendar.strftime(installed_at, "%Y-%m-%d")}"
  end

  defp installed_on_label(_installation), do: "Install date unknown"

  defp notification_channel_label(%{disconnected_at: %DateTime{}}, _routes), do: "No channel"

  defp notification_channel_label(installation, routes) do
    case configured_routes(installation, routes) do
      [] -> "Not routed"
      [route] -> route.slack_channel_id
      routes -> "#{length(routes)} channels"
    end
  end

  defp notification_channel_sublabel(_installation, _routes), do: nil

  defp notification_summary_label(%{disconnected_at: %DateTime{}}, _routes), do: "No routes"

  defp notification_summary_label(installation, routes) do
    case configured_routes(installation, routes) do
      [] -> "No routes"
      [route] -> route.label
      routes -> "#{length(routes)} routes"
    end
  end

  defp notification_summary_sublabel(%{disconnected_at: %DateTime{}}, _routes), do: nil

  defp notification_summary_sublabel(installation, routes) do
    case configured_routes(installation, routes) do
      [] -> "Configure notifications"
      [route] -> "#{length(route.events)} events"
      routes -> "#{configured_event_count(routes)} events"
    end
  end

  defp configured_routes(installation, routes) do
    routes
    |> Enum.map(fn route ->
      configured_route = Slack.notification_route_for(installation, route.object_type)

      if configured_route.slack_channel_id in [nil, ""] do
        nil
      else
        route
        |> Map.put(:slack_channel_id, configured_route.slack_channel_id)
        |> Map.put(:events, configured_route.notification_events || route.events)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp configured_event_count(routes) do
    routes
    |> Enum.flat_map(& &1.events)
    |> Enum.uniq()
    |> length()
  end

  defp notification_event_labels(route) do
    Enum.map_join(route.events, ", ", &Slack.notification_event_label/1)
  end

  defp slack_empty_title(false), do: "Slack is not configured"
  defp slack_empty_title(true), do: "No workspaces connected"

  defp slack_empty_subtitle(false) do
    "Set Slack credentials in the environment to enable workspace installs."
  end

  defp slack_empty_subtitle(true) do
    "Connect a workspace so Hive can reply in threads and capture messages as feature requests."
  end
end

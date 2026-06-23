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
            <.badge label="Ops" color="information" style="light-fill" />
            <h1>Slack</h1>
            <p>
              Connect Slack workspaces to Hive. Once installed, the bot can reply in threads
              and capture messages as feature requests.
            </p>
          </div>
        </div>

        <.card icon="brand_slack" title="Workspaces" data-part="workspaces-card">
          <:actions :if={@slack_enabled? and @installations != []}>
            <.button
              label="Connect another workspace"
              href={~p"/slack/install"}
              variant="secondary"
              size="small"
            />
          </:actions>
          <.card_section data-part="installations-section">
            <div :if={not @slack_enabled?} data-part="empty-state">
              <div data-part="empty-icon">
                <.icon name="brand_slack" />
              </div>
              <div data-part="empty-copy">
                <h2>Slack is not configured</h2>
                <p>
                  Set <code>HIVE_SLACK_CLIENT_ID</code>, <code>HIVE_SLACK_CLIENT_SECRET</code>, and
                  <code>HIVE_SLACK_SIGNING_SECRET</code> to enable workspace installs.
                </p>
              </div>
            </div>

            <div :if={@slack_enabled? and @installations == []} data-part="empty-state">
              <div data-part="empty-icon">
                <.icon name="brand_slack" />
              </div>
              <div data-part="empty-copy">
                <h2>No workspaces connected</h2>
                <p>
                  Connect a workspace so Hive can reply in threads and capture messages as feature requests.
                </p>
              </div>
              <.button
                label="Connect a Slack workspace"
                href={~p"/slack/install"}
                variant="primary"
              />
            </div>

            <div :if={@slack_enabled? and @installations != []} data-part="installations-list">
              <article :for={installation <- @installations} data-part="installation-row">
                <div data-part="workspace-icon">
                  <.icon name="brand_slack" />
                </div>

                <div data-part="workspace-main">
                  <div data-part="workspace-heading">
                    <h2>{installation.team_name || installation.team_id}</h2>
                    <.status_badge
                      :if={is_nil(installation.disconnected_at)}
                      label="Connected"
                      status="success"
                    />
                    <.status_badge
                      :if={installation.disconnected_at}
                      label="Disconnected"
                      status="disabled"
                    />
                  </div>

                  <div data-part="workspace-meta">
                    <span :if={installation.installed_by_user}>
                      Installed by {installation.installed_by_user.email}
                    </span>
                    <span :if={installation.installed_at}>
                      Installed on {Calendar.strftime(installation.installed_at, "%Y-%m-%d")}
                    </span>
                  </div>

                  <.form
                    :if={is_nil(installation.disconnected_at)}
                    for={%{}}
                    as={:installation}
                    phx-submit="save_notification_routes"
                    phx-value-id={installation.id}
                    data-part="notification-routes-form"
                  >
                    <table data-part="notification-routes-table">
                      <thead>
                        <tr>
                          <th>Object type</th>
                          <th>Slack channel</th>
                          <th>Notifications</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={route <- @notification_routes} data-part="notification-route-row">
                          <td>
                            <strong>{route.label}</strong>
                            <span>{route.description}</span>
                          </td>
                          <td>
                            <.text_input
                              id={"notification-route-#{installation.id}-#{route.object_type}"}
                              name={"installation[notification_routes][#{route.object_type}][slack_channel_id]"}
                              value={notification_channel_value(installation, route)}
                              label="Slack channel"
                              placeholder="C0123456789"
                              show_suffix={false}
                            />
                          </td>
                          <td>{notification_event_labels(route)}</td>
                        </tr>
                      </tbody>
                    </table>
                    <div data-part="notification-routes-actions">
                      <.button label="Save routes" variant="secondary" size="small" />
                    </div>
                  </.form>
                </div>

                <form
                  :if={is_nil(installation.disconnected_at)}
                  method="post"
                  action={~p"/slack/installations/#{installation.id}/disconnect"}
                  data-part="workspace-actions"
                >
                  <input type="hidden" name="_csrf_token" value={@csrf_token} />
                  <.button label="Disconnect" variant="destructive" size="small" />
                </form>
              </article>
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

  defp notification_event_labels(route) do
    Enum.map_join(route.events, ", ", &Slack.notification_event_label/1)
  end
end

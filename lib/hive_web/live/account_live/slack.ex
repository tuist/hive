defmodule HiveWeb.AccountLive.Slack do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Slack
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description: "Connect Slack workspaces to Hive.",
      eyebrow: "Account",
      highlights: ["Slack OAuth", "Workspace installs", "Message shortcuts"],
      id: "account-slack",
      path: "/account/slack",
      title: "Slack"
    }
  end

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user(session["user_id"])

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Log in to manage your account.")
         |> redirect(to: ~p"/login")}

      not Auth.member?(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Only organization members can manage Slack workspaces.")
         |> redirect(to: ~p"/account/identities")}

      true ->
        {:ok,
         socket
         |> assign(:page_title, "Slack · #{socket.assigns.product_name}")
         |> assign(OpenGraph.assigns(open_graph()))
         |> assign(:account_user, user)
         |> assign(:slack_enabled?, Slack.enabled?())
         |> assign(:installations, Slack.list_installations())}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.account
      product_name={@product_name}
      user_name={@user_name}
      user_email={@user_email}
      avatar_color={@avatar_color}
      signed_in?={@signed_in?}
      csrf_token={@csrf_token}
      current_path={@current_path}
    >
      <section id="account-slack">
        <div data-part="page-header">
          <div data-part="title-group">
            <.badge label="Account" color="information" style="light-fill" />
            <h1>Slack</h1>
            <p>
              Connect Slack workspaces to Hive. Once installed, the bot can reply in threads
              and capture messages as feature requests.
            </p>
          </div>
        </div>

        <.card icon="brand_slack" title="Workspaces">
          <.card_section data-part="installations-section">
            <p :if={not @slack_enabled?} data-part="empty-state">
              Slack is not configured on this Hive instance. Set
              <code>HIVE_SLACK_CLIENT_ID</code>, <code>HIVE_SLACK_CLIENT_SECRET</code>, and
              <code>HIVE_SLACK_SIGNING_SECRET</code> to enable workspace installs.
            </p>

            <div :if={@slack_enabled? and @installations == []} data-part="empty-state">
              <p>No workspaces are connected yet.</p>
              <.button label="Connect a Slack workspace" href={~p"/slack/install"} variant="primary" />
            </div>

            <div :if={@slack_enabled? and @installations != []} data-part="installations-list">
              <div :for={installation <- @installations} data-part="installation">
                <div data-part="installation-info">
                  <span data-part="team-name">
                    {installation.team_name || installation.team_id}
                  </span>
                  <span :if={installation.installed_by_user} data-part="installed-by">
                    Installed by {installation.installed_by_user.email}
                  </span>
                  <span :if={installation.installed_at} data-part="installed-at">
                    {Calendar.strftime(installation.installed_at, "%Y-%m-%d")}
                  </span>
                  <span :if={installation.disconnected_at} data-part="status">
                    Disconnected
                  </span>
                </div>
                <form
                  :if={is_nil(installation.disconnected_at)}
                  method="post"
                  action={~p"/slack/installations/#{installation.id}/disconnect"}
                >
                  <input type="hidden" name="_csrf_token" value={@csrf_token} />
                  <button type="submit">Disconnect</button>
                </form>
              </div>
              <.button
                label="Connect another workspace"
                href={~p"/slack/install"}
                variant="secondary"
              />
            </div>
          </.card_section>
        </.card>
      </section>
    </Layouts.account>
    """
  end
end

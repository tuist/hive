defmodule HiveWeb.AccountLive.Identities do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Slack
  alias HiveWeb.AccountComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description:
        dgettext("dashboard_account", "Manage the sign-in providers connected to your Hive user."),
      section_label: dgettext("dashboard_account", "Account"),
      highlights: [
        dgettext("dashboard_account", "Connected providers"),
        dgettext("dashboard_account", "Google sign-in"),
        dgettext("dashboard_account", "GitHub sign-in")
      ],
      id: "account-identities",
      path: "/account/identities",
      title: dgettext("dashboard_account", "Identities")
    }
  end

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_with_identities(session["user_id"])

    if user do
      {:ok,
       socket
       |> assign(
         :page_title,
         dgettext("dashboard_account", "Identities · %{product}",
           product: socket.assigns.product_name
         )
       )
       |> assign(OpenGraph.assigns(open_graph()))
       |> assign(:account_user, user)
       |> assign(:identities, Enum.sort_by(user.identities, & &1.provider))
       |> assign(:providers, Auth.providers())
       |> assign(:slack_enabled?, Slack.enabled?())
       |> assign(:slack_profiles, Slack.list_linked_user_profiles(user))}
    else
      {:ok,
       socket
       |> put_flash(:error, dgettext("dashboard_account", "Log in to manage your account."))
       |> redirect(to: ~p"/login")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.account
      flash={@flash}
      product_name={@product_name}
      user_name={@user_name}
      user_email={@user_email}
      avatar_color={@avatar_color}
      signed_in?={@signed_in?}
      csrf_token={@csrf_token}
      current_path={@current_path}
    >
      <AccountComponents.identities
        user={@account_user}
        identities={@identities}
        providers={@providers}
        slack_enabled?={@slack_enabled?}
        slack_profiles={@slack_profiles}
      />
    </Layouts.account>
    """
  end
end

defmodule HiveWeb.AccountLive.Notifications do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Accounts
  alias Hive.Domains
  alias Hive.Forage
  alias Hive.Notifications, as: NotificationSettings
  alias Hive.Specs
  alias HiveWeb.AccountComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  @global_topics %{
    "forage_new_items" => :forage_new_items,
    "spec_new" => :spec_new,
    "weekly_drop_digest" => :weekly_drop_digest
  }
  @follow_topics %{
    "forage_item_updates" => :forage_item_updates,
    "spec_updates" => :spec_updates
  }
  @cadences %{"daily" => :daily, "immediate" => :immediate}

  def open_graph do
    %{
      description: dgettext("dashboard_account", "Choose which Hive updates arrive by email."),
      section_label: dgettext("dashboard_account", "Account"),
      highlights: [
        dgettext("dashboard_account", "Forage updates"),
        dgettext("dashboard_account", "Spec updates"),
        dgettext("dashboard_account", "Domain drops")
      ],
      id: "account-notifications",
      path: "/account/notifications",
      title: dgettext("dashboard_account", "Notifications")
    }
  end

  @impl true
  def mount(_params, session, socket) do
    case Accounts.get_user(session["user_id"]) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_account", "Log in to manage your account."))
         |> redirect(to: ~p"/login")}

      user ->
        {:ok,
         socket
         |> assign(
           :page_title,
           dgettext("dashboard_account", "Notifications · %{product}",
             product: socket.assigns.product_name
           )
         )
         |> assign(OpenGraph.assigns(open_graph()))
         |> assign(:account_user, user)
         |> load_preferences()}
    end
  end

  @impl true
  def handle_event("set_global", %{"topic" => topic, "cadence" => "off"}, socket) do
    with {:ok, topic} <- fetch(@global_topics, topic) do
      NotificationSettings.unsubscribe(socket.assigns.account_user, topic)
    end

    {:noreply, load_preferences(socket)}
  end

  def handle_event("set_global", %{"topic" => topic, "cadence" => cadence}, socket) do
    with {:ok, topic} <- fetch(@global_topics, topic),
         {:ok, cadence} <- fetch(@cadences, cadence),
         true <- topic != :weekly_drop_digest or cadence == :immediate do
      NotificationSettings.subscribe(socket.assigns.account_user, topic, cadence: cadence)
    end

    {:noreply, load_preferences(socket)}
  end

  def handle_event("set_domain", %{"id" => domain_id, "cadence" => "off"}, socket) do
    if Enum.any?(socket.assigns.domains, &(&1.id == domain_id)) do
      NotificationSettings.unsubscribe(socket.assigns.account_user, :domain_drops, domain_id)
    end

    {:noreply, load_preferences(socket)}
  end

  def handle_event("set_domain", %{"id" => domain_id, "cadence" => cadence}, socket) do
    with true <- Enum.any?(socket.assigns.domains, &(&1.id == domain_id)),
         {:ok, cadence} <- fetch(@cadences, cadence) do
      NotificationSettings.subscribe(socket.assigns.account_user, :domain_drops,
        scope_id: domain_id,
        cadence: cadence
      )
    end

    {:noreply, load_preferences(socket)}
  end

  def handle_event(
        "set_follow",
        %{"topic" => topic, "id" => scope_id, "cadence" => "off"},
        socket
      ) do
    with {:ok, topic} <- fetch(@follow_topics, topic) do
      NotificationSettings.unsubscribe(socket.assigns.account_user, topic, scope_id)
    end

    {:noreply, load_preferences(socket)}
  end

  def handle_event(
        "set_follow",
        %{"topic" => topic, "id" => scope_id, "cadence" => cadence},
        socket
      ) do
    with {:ok, topic} <- fetch(@follow_topics, topic),
         {:ok, cadence} <- fetch(@cadences, cadence) do
      NotificationSettings.subscribe(socket.assigns.account_user, topic,
        scope_id: scope_id,
        cadence: cadence
      )
    end

    {:noreply, load_preferences(socket)}
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
      <AccountComponents.notifications
        email_enabled?={@email_enabled?}
        global_preferences={@global_preferences}
        domains={@domains}
        domain_preferences={@domain_preferences}
        followed_items={@followed_items}
      />
    </Layouts.account>
    """
  end

  defp load_preferences(socket) do
    user = socket.assigns.account_user
    subscriptions = NotificationSettings.list_subscriptions(user)

    global_preferences =
      Enum.map(NotificationSettings.global_topics(), fn topic ->
        %{topic: topic, cadence: cadence_for(subscriptions, topic, "global")}
      end)

    domain_preferences =
      subscriptions
      |> Enum.filter(&(&1.topic == :domain_drops))
      |> Map.new(&{&1.scope_id, &1.cadence})

    followed_items =
      subscriptions
      |> Enum.filter(&(&1.topic in [:forage_item_updates, :spec_updates]))
      |> Enum.map(&followed_item(&1, user))
      |> Enum.reject(&is_nil/1)

    socket
    |> assign(:email_enabled?, NotificationSettings.email_enabled?())
    |> assign(:global_preferences, global_preferences)
    |> assign(:domains, Domains.list_visible_domains(user))
    |> assign(:domain_preferences, domain_preferences)
    |> assign(:followed_items, followed_items)
  end

  defp followed_item(%{topic: :forage_item_updates, scope_id: item_id} = subscription, user) do
    case Forage.get_item_for_user(item_id, user) do
      {:ok, item} ->
        %{
          topic: subscription.topic,
          id: item_id,
          title: item.title,
          description: dgettext("dashboard_account", "Forage item"),
          path: HiveWeb.ForageLive.Show.item_path(item),
          cadence: subscription.cadence
        }

      _error ->
        nil
    end
  end

  defp followed_item(%{topic: :spec_updates, scope_id: spec_id} = subscription, user) do
    try do
      spec = Specs.get_spec!(spec_id)

      if Specs.can_view?(spec, user) do
        %{
          topic: subscription.topic,
          id: spec_id,
          title: spec.title,
          description: dgettext("dashboard_account", "Spec %{number}", number: spec.number),
          path: ~p"/specs/#{spec.number}",
          cadence: subscription.cadence
        }
      end
    rescue
      Ecto.NoResultsError -> nil
      Ecto.Query.CastError -> nil
    end
  end

  defp cadence_for(subscriptions, topic, scope_id) do
    case Enum.find(subscriptions, &(&1.topic == topic and &1.scope_id == scope_id)) do
      nil -> nil
      subscription -> subscription.cadence
    end
  end

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :invalid_value}
    end
  end
end

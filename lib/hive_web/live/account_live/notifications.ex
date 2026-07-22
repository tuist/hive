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
  alias HiveWeb.Utilities.Query
  alias Noora.Filter

  @page_size 10

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
         |> assign(:email_enabled?, NotificationSettings.email_enabled?())
         |> assign(:global_preferences, [])
         |> assign(:domains, [])
         |> assign(:domain_preferences, %{})
         |> assign(:followed_items, [])
         |> assign(:followed_items_meta, pagination_meta(0, 1))
         |> assign(:available_filters, follow_filters())
         |> assign(:active_filters, [])
         |> assign(:query, "")
         |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
         |> assign(:uri, URI.parse("/account/notifications"))}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    available_filters = follow_filters()
    query_params = Query.query_params(uri)
    query = params["q"] || ""
    page = Query.parse_page(params["page"])
    active_filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    {:noreply,
     socket
     |> assign(:available_filters, available_filters)
     |> load_preferences(query, active_filters, page, uri_from_query_params(query_params))}
  end

  @impl true
  def handle_event("set_global", %{"topic" => topic, "cadence" => "off"}, socket) do
    with {:ok, topic} <- fetch(@global_topics, topic) do
      NotificationSettings.unsubscribe(socket.assigns.account_user, topic)
    end

    {:noreply, reload_preferences(socket)}
  end

  def handle_event("set_global", %{"topic" => topic, "cadence" => cadence}, socket) do
    with {:ok, topic} <- fetch(@global_topics, topic),
         {:ok, cadence} <- fetch(@cadences, cadence),
         true <- topic != :weekly_drop_digest or cadence == :immediate do
      NotificationSettings.subscribe(socket.assigns.account_user, topic, cadence: cadence)
    end

    {:noreply, reload_preferences(socket)}
  end

  def handle_event("set_domain", %{"id" => domain_id, "cadence" => "off"}, socket) do
    if Enum.any?(socket.assigns.domains, &(&1.id == domain_id)) do
      NotificationSettings.unsubscribe(socket.assigns.account_user, :domain_drops, domain_id)
    end

    {:noreply, reload_preferences(socket)}
  end

  def handle_event("set_domain", %{"id" => domain_id, "cadence" => cadence}, socket) do
    with true <- Enum.any?(socket.assigns.domains, &(&1.id == domain_id)),
         {:ok, cadence} <- fetch(@cadences, cadence) do
      NotificationSettings.subscribe(socket.assigns.account_user, :domain_drops,
        scope_id: domain_id,
        cadence: cadence
      )
    end

    {:noreply, reload_preferences(socket)}
  end

  def handle_event(
        "set_follow",
        %{"topic" => topic, "id" => scope_id, "cadence" => "off"},
        socket
      ) do
    with {:ok, topic} <- fetch(@follow_topics, topic) do
      NotificationSettings.unsubscribe(socket.assigns.account_user, topic, scope_id)
    end

    {:noreply, reload_preferences(socket)}
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

    {:noreply, reload_preferences(socket)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/account/notifications?#{following_query_params(query, socket.assigns.active_filters)}",
       replace: true
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Filter.Operations.add_filter_to_query(filter_id, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/account/notifications?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Filter.Operations.update_filters_in_query(params, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/account/notifications?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
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
        followed_items_meta={@followed_items_meta}
        available_filters={@available_filters}
        active_filters={@active_filters}
        search_form={@search_form}
        query={@query}
        uri={@uri}
      />
    </Layouts.account>
    """
  end

  defp reload_preferences(socket) do
    load_preferences(
      socket,
      socket.assigns.query,
      socket.assigns.active_filters,
      socket.assigns.followed_items_meta.current_page,
      socket.assigns.uri
    )
  end

  defp load_preferences(socket, query, active_filters, page, uri) do
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
      |> filter_followed_items(query, active_filters)

    {followed_items, followed_items_meta} = paginate(followed_items, page)

    socket
    |> assign(:email_enabled?, NotificationSettings.email_enabled?())
    |> assign(:global_preferences, global_preferences)
    |> assign(:domains, Domains.list_visible_domains(user))
    |> assign(:domain_preferences, domain_preferences)
    |> assign(:followed_items, followed_items)
    |> assign(:followed_items_meta, followed_items_meta)
    |> assign(:active_filters, active_filters)
    |> assign(:query, query)
    |> assign(:search_form, to_form(%{"query" => query}, as: :search))
    |> assign(:uri, uri)
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

  defp filter_followed_items(items, query, active_filters) do
    items
    |> filter_followed_items_by_query(Query.present_string(query))
    |> filter_followed_items_by_kind(Enum.find(active_filters, &(&1.id == "kind")))
  end

  defp filter_followed_items_by_query(items, nil), do: items

  defp filter_followed_items_by_query(items, query) do
    query = String.downcase(query)

    Enum.filter(items, fn item ->
      item
      |> Map.take([:title, :description])
      |> Map.values()
      |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), query)))
    end)
  end

  defp filter_followed_items_by_kind(items, %{operator: :==, value: value}) do
    Enum.filter(items, &(Atom.to_string(&1.topic) == value))
  end

  defp filter_followed_items_by_kind(items, %{operator: :!=, value: value}) do
    Enum.reject(items, &(Atom.to_string(&1.topic) == value))
  end

  defp filter_followed_items_by_kind(items, _filter), do: items

  defp paginate(items, page) do
    total_entries = length(items)
    total_pages = max(1, div(total_entries + @page_size - 1, @page_size))
    current_page = min(page, total_pages)
    offset = (current_page - 1) * @page_size

    {Enum.slice(items, offset, @page_size), pagination_meta(total_entries, current_page)}
  end

  defp pagination_meta(total_entries, current_page) do
    %{
      current_page: current_page,
      page_size: @page_size,
      total_entries: total_entries,
      total_pages: max(1, div(total_entries + @page_size - 1, @page_size))
    }
  end

  defp following_query_params(query, active_filters) do
    active_filters
    |> Filter.Operations.encode_filters_to_query()
    |> Query.put_present("q", Query.present_string(query))
  end

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp uri_from_query_params(params) do
    case URI.encode_query(params) do
      "" -> URI.parse("")
      query -> URI.parse("?" <> query)
    end
  end

  defp follow_filters do
    [
      %Filter.Filter{
        id: "kind",
        display_name: dgettext("dashboard_account", "Kind"),
        type: :option,
        options: ["forage_item_updates", "spec_updates"],
        options_display_names: %{
          "forage_item_updates" => dgettext("dashboard_account", "Forage item"),
          "spec_updates" => dgettext("dashboard_account", "Spec")
        },
        operator: :==,
        searchable: false,
        value: nil
      }
    ]
  end

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :invalid_value}
    end
  end
end

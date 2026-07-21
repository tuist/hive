defmodule Hive.Notifications do
  @moduledoc """
  User-controlled subscriptions and durable notification events.

  Product contexts write events in the same database transaction as the
  change they describe. A dispatcher turns committed events into per-user
  deliveries, while delivery workers render against current authorization.
  """

  import Ecto.Query

  alias Hive.Accounts.User
  alias Hive.Notifications.Delivery
  alias Hive.Notifications.DeliveryWorker
  alias Hive.Notifications.Event
  alias Hive.Notifications.Subscription
  alias Hive.Repo

  @global_scope "global"
  @daily_delivery_hour 8

  def email_enabled? do
    case Keyword.get(Application.get_env(:hive, :email, []), :from) do
      {name, address}
      when is_binary(name) and name != "" and is_binary(address) and address != "" ->
        true

      address when is_binary(address) and address != "" ->
        true

      _other ->
        false
    end
  end

  def global_topics, do: [:forage_new_items, :spec_new, :weekly_drop_digest]

  def topic_label(:forage_new_items), do: "New Forage items"
  def topic_label(:forage_item_updates), do: "Followed Forage item updates"
  def topic_label(:spec_new), do: "New specs"
  def topic_label(:spec_updates), do: "Followed spec updates"
  def topic_label(:domain_drops), do: "New domain drops"
  def topic_label(:weekly_drop_digest), do: "Weekly drop digest"

  def cadence_label(:immediate), do: "Immediately"
  def cadence_label(:daily), do: "Daily summary"

  def list_subscriptions(%User{id: user_id}) do
    Subscription
    |> where([subscription], subscription.user_id == ^user_id)
    |> order_by([subscription], asc: subscription.topic, asc: subscription.scope_id)
    |> Repo.all()
  end

  def list_subscriptions(_user), do: []

  def list_subscriptions(%User{id: user_id}, topic) when is_atom(topic) do
    Subscription
    |> where([subscription], subscription.user_id == ^user_id)
    |> where([subscription], subscription.topic == ^topic)
    |> order_by([subscription], asc: subscription.scope_id)
    |> Repo.all()
  end

  def list_subscriptions(_user, _topic), do: []

  def get_subscription(user, topic, scope_id \\ @global_scope)

  def get_subscription(%User{id: user_id}, topic, scope_id)
      when is_atom(topic) and is_binary(scope_id) do
    {scope_type, normalized_scope_id} = scope_for(topic, scope_id)

    Repo.get_by(Subscription,
      user_id: user_id,
      topic: topic,
      scope_type: scope_type,
      scope_id: normalized_scope_id
    )
  end

  def get_subscription(_user, _topic, _scope_id), do: nil

  def subscribed?(user, topic, scope_id \\ @global_scope),
    do: not is_nil(get_subscription(user, topic, scope_id))

  def subscribe(%User{} = user, topic, opts \\ []) when is_atom(topic) do
    put_subscription(user, topic, opts, true)
  end

  def ensure_subscription(%User{} = user, topic, opts \\ []) when is_atom(topic) do
    put_subscription(user, topic, opts, false)
  end

  defp put_subscription(%User{} = user, topic, opts, replace_cadence?) do
    scope_id = Keyword.get(opts, :scope_id, @global_scope)
    cadence = Keyword.get(opts, :cadence, default_cadence(topic))
    {scope_type, normalized_scope_id} = scope_for(topic, scope_id)

    changeset =
      Subscription.changeset(%Subscription{}, %{
        user_id: user.id,
        topic: topic,
        scope_type: scope_type,
        scope_id: normalized_scope_id,
        cadence: cadence
      })

    on_conflict =
      if replace_cadence?, do: [set: [cadence: cadence, updated_at: now()]], else: :nothing

    Repo.insert(changeset,
      on_conflict: on_conflict,
      conflict_target: [:user_id, :topic, :scope_type, :scope_id],
      returning: true
    )
  end

  def unsubscribe(%User{id: user_id}, topic, scope_id \\ @global_scope)
      when is_atom(topic) and is_binary(scope_id) do
    {scope_type, normalized_scope_id} = scope_for(topic, scope_id)

    {count, _rows} =
      Subscription
      |> where([subscription], subscription.user_id == ^user_id)
      |> where([subscription], subscription.topic == ^topic)
      |> where([subscription], subscription.scope_type == ^scope_type)
      |> where([subscription], subscription.scope_id == ^normalized_scope_id)
      |> Repo.delete_all()

    if count == 0, do: :not_found, else: :ok
  end

  def unsubscribe_topic(%User{id: user_id}, topic) when is_atom(topic) do
    Subscription
    |> where([subscription], subscription.user_id == ^user_id)
    |> where([subscription], subscription.topic == ^topic)
    |> Repo.delete_all()

    :ok
  end

  def follow_forage_item(%User{} = user, item_id, opts \\ []) when is_binary(item_id) do
    subscribe(user, :forage_item_updates, Keyword.put(opts, :scope_id, item_id))
  end

  def follow_spec(%User{} = user, spec_id, opts \\ []) when is_binary(spec_id) do
    subscribe(user, :spec_updates, Keyword.put(opts, :scope_id, spec_id))
  end

  def ensure_forage_item_follow(%User{} = user, item_id, opts \\ []) when is_binary(item_id) do
    ensure_subscription(user, :forage_item_updates, Keyword.put(opts, :scope_id, item_id))
  end

  def ensure_spec_follow(%User{} = user, spec_id, opts \\ []) when is_binary(spec_id) do
    ensure_subscription(user, :spec_updates, Keyword.put(opts, :scope_id, spec_id))
  end

  def followers(topic, scope_id) when topic in [:forage_item_updates, :spec_updates] do
    {scope_type, normalized_scope_id} = scope_for(topic, scope_id)

    Subscription
    |> where([subscription], subscription.topic == ^topic)
    |> where([subscription], subscription.scope_type == ^scope_type)
    |> where([subscription], subscription.scope_id == ^normalized_scope_id)
    |> preload(:user)
    |> Repo.all()
  end

  def publish(attrs) when is_map(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: :deduplication_key,
      returning: true
    )
  end

  def publish!(attrs) when is_map(attrs) do
    case publish(attrs) do
      {:ok, event} ->
        event

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end

  def pending_events(limit \\ 100) do
    Event
    |> where([event], is_nil(event.dispatched_at))
    |> order_by([event], asc: event.occurred_at, asc: event.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def dispatch(%Event{} = event) do
    Repo.transaction(fn ->
      timestamp = now()

      rows =
        event
        |> matching_subscriptions()
        |> Enum.reject(&(&1.user_id == event.actor_id))
        |> Enum.group_by(& &1.user_id)
        |> Enum.map(fn {user_id, user_subscriptions} ->
          cadence = preferred_cadence(user_subscriptions)

          %{
            id: Ecto.UUID.generate(),
            event_id: event.id,
            user_id: user_id,
            topic: topic_for(event.type),
            cadence: cadence,
            status: :pending,
            scheduled_at: scheduled_at(cadence, event.occurred_at),
            inserted_at: timestamp,
            updated_at: timestamp
          }
        end)

      Repo.insert_all(Delivery, rows,
        on_conflict: :nothing,
        conflict_target: [:event_id, :user_id, :topic]
      )

      event
      |> Event.changeset(%{dispatched_at: now()})
      |> Repo.update!()
    end)
  end

  def dispatch_pending(limit \\ 100) do
    pending_events(limit)
    |> Enum.each(&dispatch/1)

    enqueue_pending_deliveries()
    :ok
  end

  def enqueue_pending_deliveries do
    Delivery
    |> where([delivery], delivery.status == :pending)
    |> order_by([delivery], asc: delivery.scheduled_at)
    |> limit(500)
    |> Repo.all()
    |> Enum.each(&DeliveryWorker.enqueue/1)

    :ok
  end

  def get_delivery(id) when is_binary(id) do
    Delivery
    |> preload([:event, :user])
    |> Repo.get(id)
  end

  def get_due_daily_delivery(user_id, topic) when is_binary(user_id) and is_binary(topic) do
    topics = Map.new(Subscription.topics(), &{Atom.to_string(&1), &1})

    case Map.get(topics, topic) do
      topic when is_atom(topic) -> due_daily_delivery(user_id, topic)
      _invalid_topic -> nil
    end
  end

  defp due_daily_delivery(user_id, topic) do
    Delivery
    |> where([delivery], delivery.user_id == ^user_id)
    |> where([delivery], delivery.topic == ^topic)
    |> where([delivery], delivery.cadence == :daily)
    |> where([delivery], delivery.status == :pending)
    |> where([delivery], delivery.scheduled_at <= ^now())
    |> order_by([delivery], asc: delivery.scheduled_at, asc: delivery.id)
    |> limit(1)
    |> preload([:event, :user])
    |> Repo.one()
  end

  def due_daily_deliveries(%Delivery{} = delivery, now \\ DateTime.utc_now()) do
    Delivery
    |> where([candidate], candidate.user_id == ^delivery.user_id)
    |> where([candidate], candidate.topic == ^delivery.topic)
    |> where([candidate], candidate.cadence == :daily)
    |> where([candidate], candidate.status == :pending)
    |> where([candidate], candidate.scheduled_at <= ^DateTime.truncate(now, :second))
    |> order_by([candidate], asc: candidate.scheduled_at, asc: candidate.id)
    |> preload([:event, :user])
    |> Repo.all()
  end

  def current_subscription_for_delivery?(%Delivery{event: %Event{} = event, user: %User{} = user}) do
    event
    |> matching_subscriptions(user.id)
    |> Enum.any?()
  end

  def current_subscription_for_delivery?(%Delivery{} = delivery) do
    delivery
    |> Repo.preload([:event, :user])
    |> current_subscription_for_delivery?()
  end

  def mark_sent(deliveries, provider_message_id \\ nil) do
    ids = Enum.map(List.wrap(deliveries), & &1.id)

    Delivery
    |> where([delivery], delivery.id in ^ids and delivery.status == :pending)
    |> Repo.update_all(
      set: [
        status: :sent,
        sent_at: now(),
        provider_message_id: provider_message_id,
        last_error: nil,
        updated_at: now()
      ]
    )

    :ok
  end

  def mark_skipped(deliveries, reason) do
    ids = Enum.map(List.wrap(deliveries), & &1.id)

    Delivery
    |> where([delivery], delivery.id in ^ids and delivery.status == :pending)
    |> Repo.update_all(set: [status: :skipped, skip_reason: to_string(reason), updated_at: now()])

    :ok
  end

  def mark_failed(deliveries, reason, opts \\ []) do
    ids = Enum.map(List.wrap(deliveries), & &1.id)
    error = reason |> inspect() |> String.slice(0, 1_000)
    status = if Keyword.get(opts, :terminal, false), do: :failed, else: :pending

    Delivery
    |> where([delivery], delivery.id in ^ids and delivery.status == :pending)
    |> Repo.update_all(set: [status: status, last_error: error, updated_at: now()])

    :ok
  end

  def topic_for(type)

  def topic_for(:forage_item_created), do: :forage_new_items

  def topic_for(type)
      when type in [
             :forage_item_updated,
             :forage_comment_created,
             :forage_spec_created,
             :forage_flight_completed
           ],
      do: :forage_item_updates

  def topic_for(:spec_created), do: :spec_new

  def topic_for(type)
      when type in [:spec_updated, :spec_comment_created, :spec_review_requested],
      do: :spec_updates

  def topic_for(:drop_published), do: :domain_drops
  def topic_for(:weekly_drop_digest_published), do: :weekly_drop_digest

  defp matching_subscriptions(%Event{} = event, user_id \\ nil) do
    topic = topic_for(event.type)

    Subscription
    |> where([subscription], subscription.topic == ^topic)
    |> maybe_filter_user(user_id)
    |> match_scope(event, topic)
    |> Repo.all()
  end

  defp match_scope(query, _event, topic)
       when topic in [:forage_new_items, :spec_new, :weekly_drop_digest] do
    where(
      query,
      [subscription],
      subscription.scope_type == :global and subscription.scope_id == ^@global_scope
    )
  end

  defp match_scope(query, %Event{resource_id: resource_id}, :forage_item_updates) do
    where(
      query,
      [subscription],
      subscription.scope_type == :forage_item and subscription.scope_id == ^resource_id
    )
  end

  defp match_scope(query, %Event{resource_id: resource_id}, :spec_updates) do
    where(
      query,
      [subscription],
      subscription.scope_type == :spec and subscription.scope_id == ^resource_id
    )
  end

  defp match_scope(query, %Event{data: data}, :domain_drops) do
    domain_ids = Map.get(data || %{}, "domain_ids", [])

    where(
      query,
      [subscription],
      subscription.scope_type == :domain and subscription.scope_id in ^domain_ids
    )
  end

  defp maybe_filter_user(query, nil), do: query

  defp maybe_filter_user(query, user_id),
    do: where(query, [subscription], subscription.user_id == ^user_id)

  defp scope_for(topic, _scope_id)
       when topic in [:forage_new_items, :spec_new, :weekly_drop_digest],
       do: {:global, @global_scope}

  defp scope_for(:forage_item_updates, scope_id), do: {:forage_item, scope_id}
  defp scope_for(:spec_updates, scope_id), do: {:spec, scope_id}
  defp scope_for(:domain_drops, scope_id), do: {:domain, scope_id}

  defp default_cadence(:weekly_drop_digest), do: :immediate
  defp default_cadence(_topic), do: :daily

  defp preferred_cadence(subscriptions) do
    if Enum.any?(subscriptions, &(&1.cadence == :immediate)), do: :immediate, else: :daily
  end

  defp scheduled_at(:immediate, occurred_at), do: occurred_at || now()

  defp scheduled_at(:daily, occurred_at) do
    occurred_at = occurred_at || now()
    date = DateTime.to_date(occurred_at)
    today_delivery = DateTime.new!(date, Time.new!(@daily_delivery_hour, 0, 0))

    if DateTime.compare(occurred_at, today_delivery) == :lt do
      today_delivery
    else
      date |> Date.add(1) |> DateTime.new!(Time.new!(@daily_delivery_hour, 0, 0))
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end

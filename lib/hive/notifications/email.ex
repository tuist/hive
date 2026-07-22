defmodule Hive.Notifications.Email do
  @moduledoc false

  import Swoosh.Email

  alias Hive.Drops
  alias Hive.Drops.WeeklyDigest
  alias Hive.Forage
  alias Hive.Notifications
  alias Hive.Notifications.Delivery
  alias Hive.Notifications.Event
  alias Hive.Notifications.Mailer
  alias Hive.Repo
  alias Hive.Specs
  alias Hive.Specs.Spec
  alias HiveWeb.Endpoint

  @unsubscribe_salt "notification-unsubscribe"
  @unsubscribe_max_age 60 * 60 * 24 * 365 * 10

  def deliver_immediate(%Delivery{} = delivery) do
    delivery = Repo.preload(delivery, [:event, :user])

    cond do
      not Notifications.email_enabled?() ->
        Notifications.mark_skipped(delivery, :email_not_configured)

      not Notifications.current_subscription_for_delivery?(delivery) ->
        Notifications.mark_skipped(delivery, :unsubscribed)

      true ->
        case entry(delivery.event, delivery.user) do
          {:ok, entry} ->
            deliver_entries([delivery], [entry], delivery.user, delivery.topic, false)

          {:skip, reason} ->
            Notifications.mark_skipped(delivery, reason)
        end
    end
  end

  def deliver_daily(%Delivery{} = delivery) do
    if Notifications.email_enabled?() do
      do_deliver_daily(delivery)
    else
      delivery
      |> Notifications.due_daily_deliveries()
      |> Notifications.mark_skipped(:email_not_configured)
    end
  end

  defp do_deliver_daily(delivery) do
    deliveries = Notifications.due_daily_deliveries(delivery)

    {deliverable, skipped} =
      Enum.split_with(deliveries, &Notifications.current_subscription_for_delivery?/1)

    if skipped != [], do: Notifications.mark_skipped(skipped, :unsubscribed)

    {entries, unauthorized} =
      Enum.reduce(deliverable, {[], []}, fn candidate, {entries, unauthorized} ->
        case entry(candidate.event, candidate.user) do
          {:ok, entry} -> {[entry | entries], unauthorized}
          {:skip, _reason} -> {entries, [candidate | unauthorized]}
        end
      end)

    if unauthorized != [], do: Notifications.mark_skipped(unauthorized, :unauthorized)

    case Enum.reverse(entries) do
      [] ->
        :ok

      entries ->
        deliver_entries(deliverable -- unauthorized, entries, delivery.user, delivery.topic, true)
    end
  end

  @doc """
  Signs an unsubscribe link.

  `scope_id` narrows the link to the single resource the message is about,
  so stopping updates from a message about one spec does not throw away
  the reader's other follows. A `nil` scope covers the whole topic, which
  is what a summary spanning several resources has to offer.
  """
  def unsubscribe_token(%{id: user_id}, topic, scope_id \\ nil)
      when is_atom(topic) and (is_nil(scope_id) or is_binary(scope_id)) do
    Phoenix.Token.sign(Endpoint, @unsubscribe_salt, {user_id, Atom.to_string(topic), scope_id})
  end

  def verify_unsubscribe_token(token) when is_binary(token) do
    topics = Map.new(Hive.Notifications.Subscription.topics(), &{Atom.to_string(&1), &1})

    with {:ok, {user_id, topic, scope_id}}
         when is_binary(user_id) and (is_nil(scope_id) or is_binary(scope_id)) <-
           Phoenix.Token.verify(Endpoint, @unsubscribe_salt, token, max_age: @unsubscribe_max_age),
         topic when is_atom(topic) <- Map.get(topics, topic) do
      {:ok, user_id, topic, scope_id}
    else
      _error -> {:error, :invalid_token}
    end
  end

  def verify_unsubscribe_token(_token), do: {:error, :invalid_token}

  defp deliver_entries(deliveries, entries, user, topic, daily?) do
    email = build_email(user, topic, entries, daily?, unsubscribe_scope(deliveries, topic))

    case Mailer.deliver(email) do
      {:ok, metadata} ->
        Notifications.mark_sent(deliveries, provider_message_id(metadata))

      {:error, reason} ->
        Notifications.mark_failed(deliveries, reason)
        {:error, reason}
    end
  end

  defp unsubscribe_scope(deliveries, topic) do
    if Notifications.resource_scoped_topic?(topic) do
      deliveries
      |> Enum.map(& &1.event.resource_id)
      |> Enum.uniq()
      |> case do
        [resource_id] -> resource_id
        _several -> nil
      end
    end
  end

  defp build_email(user, topic, entries, daily?, scope_id) do
    unsubscribe_url = unsubscribe_url(user, topic, scope_id)

    label = unsubscribe_label(topic, scope_id)

    new()
    |> from(email_from())
    |> to({user.name || user.email, user.email})
    |> subject(subject(topic, entries, daily?))
    |> text_body(text_body(topic, entries, unsubscribe_url, label))
    |> html_body(html_body(topic, entries, unsubscribe_url, label))
    |> header("List-Unsubscribe", "<#{unsubscribe_url}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
    |> maybe_put_message_stream()
  end

  defp entry(%Event{resource_type: "forage_item", resource_id: item_id} = event, user) do
    case Forage.get_item_for_user(item_id, user) do
      {:ok, item} ->
        {:ok,
         %{
           title: item.title,
           description: forage_description(event, item),
           label: event_label(event.type),
           url: absolute_url(HiveWeb.ForageLive.Show.item_path(item)),
           occurred_at: event.occurred_at
         }}

      _error ->
        {:skip, :unauthorized}
    end
  end

  defp entry(%Event{resource_type: "spec", resource_id: spec_id} = event, user) do
    case Repo.get(Spec, spec_id) do
      %Spec{} = spec when not is_nil(user) ->
        if Specs.can_view?(spec, user) do
          {:ok,
           %{
             title: spec.title,
             description: spec_description(event, spec),
             label: event_label(event.type),
             url: absolute_url("/specs/#{spec.number}"),
             occurred_at: event.occurred_at
           }}
        else
          {:skip, :unauthorized}
        end

      _missing ->
        {:skip, :not_found}
    end
  end

  defp entry(%Event{resource_type: "drop", resource_id: drop_id} = event, user) do
    case Drops.fetch_visible_drop(drop_id, user) do
      {:ok, drop} ->
        {:ok,
         %{
           title: drop.title,
           description: drop.body || "A new drop was published.",
           label: event_label(event.type),
           url: absolute_url(Drops.public_path(drop)),
           occurred_at: event.occurred_at
         }}

      _error ->
        {:skip, :unauthorized}
    end
  end

  defp entry(%Event{resource_type: "drop_digest", resource_id: digest_id} = event, _user) do
    case Repo.get(WeeklyDigest, digest_id) do
      %WeeklyDigest{status: :published} = digest ->
        {:ok,
         %{
           title: digest.title,
           description: digest.summary,
           label: event_label(event.type),
           url: absolute_url(Hive.Drops.WeeklyDigests.public_path(digest)),
           occurred_at: event.occurred_at
         }}

      _missing_or_unpublished ->
        {:skip, :not_found}
    end
  end

  defp entry(_event, _user), do: {:skip, :unknown_event}

  defp forage_description(%Event{type: :forage_comment_created, data: data}, _item),
    do: Map.get(data, "comment_preview", "A new comment was added.")

  defp forage_description(%Event{type: :forage_spec_created, data: data}, _item),
    do: Map.get(data, "spec_title", "A spec was created from this item.")

  defp forage_description(%Event{type: :forage_flight_completed, data: data}, _item) do
    status = Map.get(data, "status", "completed")
    "A Flight #{status}."
  end

  defp forage_description(%Event{type: :forage_item_updated, data: data}, item),
    do: Map.get(data, "description", item.body || "The item was updated.")

  defp forage_description(_event, item), do: item.body || "A new item appeared in Forage."

  defp spec_description(%Event{type: :spec_comment_created, data: data}, _spec),
    do: Map.get(data, "comment_preview", "A new comment was added.")

  defp spec_description(%Event{type: :spec_review_requested}, _spec),
    do: "Review was requested for this spec."

  defp spec_description(%Event{type: :spec_updated, data: data}, spec),
    do: Map.get(data, "description", spec.summary || "The spec was updated.")

  defp spec_description(_event, spec), do: spec.summary || "A new spec was created."

  defp event_label(:forage_item_created), do: "New Forage item"
  defp event_label(:forage_item_updated), do: "Forage item updated"
  defp event_label(:forage_comment_created), do: "New Forage comment"
  defp event_label(:forage_spec_created), do: "Spec created from Forage"
  defp event_label(:forage_flight_completed), do: "Flight completed"
  defp event_label(:spec_created), do: "New spec"
  defp event_label(:spec_updated), do: "Spec updated"
  defp event_label(:spec_comment_created), do: "New spec comment"
  defp event_label(:spec_review_requested), do: "Spec review requested"
  defp event_label(:drop_published), do: "New domain drop"
  defp event_label(:weekly_drop_digest_published), do: "Weekly drop digest"

  defp subject(_topic, [entry], false), do: "#{entry.label}: #{entry.title}"

  defp subject(topic, entries, true) do
    "#{Notifications.topic_label(topic)}: #{length(entries)} updates"
  end

  defp unsubscribe_label(topic, nil), do: Notifications.topic_label(topic)
  defp unsubscribe_label(_topic, _scope_id), do: "these updates"

  defp text_body(topic, entries, unsubscribe_url, unsubscribe_label) do
    entries_text =
      Enum.map_join(entries, "\n\n", fn entry ->
        "#{entry.label}\n#{entry.title}\n#{entry.description}\n#{entry.url}"
      end)

    """
    #{Notifications.topic_label(topic)}

    #{entries_text}

    Manage notifications: #{absolute_url("/account/notifications")}
    Unsubscribe from #{unsubscribe_label}: #{unsubscribe_url}
    """
  end

  defp html_body(topic, entries, unsubscribe_url, unsubscribe_label) do
    entries_html =
      Enum.map_join(entries, "", fn entry ->
        """
        <article style="margin:0 0 24px">
          <p style="margin:0 0 4px;color:#667085;font-size:13px">#{escape(entry.label)}</p>
          <h2 style="margin:0 0 8px;font-size:18px">#{escape(entry.title)}</h2>
          <p style="margin:0 0 12px;color:#475467">#{escape(truncate(entry.description))}</p>
          <a href="#{escape(entry.url)}">View in Hive</a>
        </article>
        """
      end)

    """
    <!doctype html>
    <html lang="en">
      <body style="margin:0;background:#f8fafc;color:#101828;font-family:system-ui,sans-serif">
        <main style="max-width:640px;margin:0 auto;padding:32px 24px;background:#ffffff">
          <h1 style="margin:0 0 24px;font-size:22px">#{escape(Notifications.topic_label(topic))}</h1>
          #{entries_html}
          <footer style="margin-top:32px;padding-top:20px;border-top:1px solid #eaecf0;color:#667085;font-size:13px">
            <a href="#{escape(absolute_url("/account/notifications"))}">Manage notifications</a>
            <span> · </span>
            <a href="#{escape(unsubscribe_url)}">Unsubscribe from #{escape(unsubscribe_label)}</a>
          </footer>
        </main>
      </body>
    </html>
    """
  end

  defp unsubscribe_url(user, topic, scope_id) do
    token = unsubscribe_token(user, topic, scope_id)
    absolute_url("/notifications/unsubscribe?token=#{URI.encode_www_form(token)}")
  end

  defp absolute_url(path), do: Endpoint.url() <> path

  defp email_from, do: Notifications.email_from()

  defp maybe_put_message_stream(email) do
    case Keyword.get(Application.get_env(:hive, :email, []), :message_stream) do
      stream when is_binary(stream) and stream != "" ->
        put_provider_option(email, :message_stream, stream)

      _other ->
        email
    end
  end

  defp provider_message_id(metadata) when is_map(metadata) do
    metadata[:message_id] || metadata["MessageID"] || metadata["message_id"]
  end

  defp provider_message_id(_metadata), do: nil

  defp truncate(value) when is_binary(value) do
    if String.length(value) > 500, do: String.slice(value, 0, 497) <> "...", else: value
  end

  defp truncate(_value), do: ""

  defp escape(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end

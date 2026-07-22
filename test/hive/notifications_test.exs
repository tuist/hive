defmodule Hive.NotificationsTest do
  use Hive.DataCase, async: true
  use Oban.Testing, repo: Hive.Repo

  import Swoosh.TestAssertions

  alias Hive.Accounts
  alias Hive.Forage
  alias Hive.Notifications
  alias Hive.Notifications.Delivery
  alias Hive.Notifications.Email
  alias Hive.Notifications.Event
  alias Hive.Notifications.DeliveryWorker
  alias Hive.Projects
  alias Hive.Repo
  alias Hive.Specs

  defp user(email) do
    {:ok, user} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    user
  end

  test "the configured sender may carry a display name" do
    assert Notifications.parse_sender("Hive <notifications@example.com>") ==
             {"Hive", "notifications@example.com"}

    assert Notifications.parse_sender("\"Hive Updates\" <notifications@example.com>") ==
             {"Hive Updates", "notifications@example.com"}

    assert Notifications.parse_sender("notifications@example.com") ==
             {"", "notifications@example.com"}

    assert Notifications.parse_sender({"Hive", "notifications@example.com"}) ==
             {"Hive", "notifications@example.com"}

    assert Notifications.parse_sender("   ") == nil
    assert Notifications.parse_sender(nil) == nil
  end

  test "a long provider error is recorded rather than rejected by the database" do
    follower = user("follower@example.com")
    delivery = pending_delivery(follower, DateTime.utc_now())
    reason = {:no_more_hosts, String.duplicate("permanent failure from the relay ", 20)}

    assert :ok = Notifications.mark_failed(delivery, reason, terminal: true)

    stored = Repo.get!(Delivery, delivery.id)
    assert stored.status == :failed
    assert String.length(stored.last_error) > 255
  end

  test "a delivery is enqueued when it is dispatched" do
    actor = user("actor@example.com")
    follower = user("follower@example.com")
    Notifications.subscribe(follower, :forage_new_items, cadence: :immediate)

    {:ok, _item} =
      Forage.create_feature_request(
        %{"title" => "Enqueue on dispatch", "description" => "Deliveries should not wait."},
        actor
      )

    event = Repo.get_by!(Event, type: :forage_item_created)

    assert {:ok, _event} = Notifications.dispatch(event)
    assert [_job] = all_enqueued(worker: DeliveryWorker)
  end

  test "the recovery sweep only picks up deliveries that are already due" do
    follower = user("follower@example.com")
    future = DateTime.utc_now() |> DateTime.add(7, :day)
    delivery = pending_delivery(follower, future)

    assert :ok = Notifications.enqueue_pending_deliveries()
    assert all_enqueued(worker: DeliveryWorker) == []

    delivery
    |> Ecto.Changeset.change(scheduled_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update!()

    assert :ok = Notifications.enqueue_pending_deliveries()
    assert [_job] = all_enqueued(worker: DeliveryWorker)
  end

  defp pending_delivery(user, scheduled_at) do
    {:ok, event} =
      Notifications.publish(%{
        deduplication_key: "forage_item_created:#{Ecto.UUID.generate()}",
        type: :forage_item_created,
        resource_type: "forage_item",
        resource_id: "manual:#{Ecto.UUID.generate()}"
      })

    Repo.insert!(%Delivery{
      event_id: event.id,
      user_id: user.id,
      topic: :forage_new_items,
      cadence: :immediate,
      status: :pending,
      scheduled_at: DateTime.truncate(scheduled_at, :second)
    })
  end

  test "subscriptions are unique and automatic follows preserve a chosen cadence" do
    user = user("follower@example.com")

    assert {:ok, subscription} =
             Notifications.follow_spec(user, Ecto.UUID.generate(), cadence: :immediate)

    assert subscription.cadence == :immediate

    assert {:ok, _subscription} =
             Notifications.ensure_spec_follow(user, subscription.scope_id, cadence: :daily)

    assert Notifications.get_subscription(user, :spec_updates, subscription.scope_id).cadence ==
             :immediate

    assert length(Notifications.list_subscriptions(user, :spec_updates)) == 1
  end

  test "dispatch fans an event out to subscribers but not to its actor" do
    actor = user("actor@example.com")
    follower = user("follower@example.com")

    Notifications.subscribe(actor, :forage_new_items, cadence: :immediate)
    Notifications.subscribe(follower, :forage_new_items, cadence: :immediate)

    {:ok, item} =
      Forage.create_feature_request(
        %{"title" => "Email updates", "description" => "Send useful product updates by email."},
        actor
      )

    assert %Event{type: :forage_item_created, resource_id: "manual:" <> item_id} =
             Repo.get_by!(Event, type: :forage_item_created)

    assert item_id == item.id
    assert :ok = Notifications.dispatch_pending()

    assert %Delivery{user_id: user_id, cadence: :immediate, status: :pending} =
             delivery =
             Repo.one!(Delivery)

    assert user_id == follower.id
    assert :ok = Email.deliver_immediate(delivery)

    assert_email_sent(fn email ->
      assert email.to == [{follower.email, follower.email}]
      assert email.subject =~ "New Forage item"
      assert email.html_body =~ "Email updates"
      assert Map.has_key?(email.headers, "List-Unsubscribe")
    end)

    assert Repo.get!(Delivery, delivery.id).status == :sent
  end

  test "delivery checks the current subscription before sending" do
    actor = user("actor@example.com")
    follower = user("follower@example.com")
    Notifications.subscribe(follower, :forage_new_items, cadence: :immediate)

    {:ok, _item} =
      Forage.create_feature_request(
        %{"title" => "Digest", "description" => "Collect updates into a useful digest."},
        actor
      )

    :ok = Notifications.dispatch_pending()
    delivery = Repo.one!(Delivery)
    :ok = Notifications.unsubscribe(follower, :forage_new_items)

    assert :ok = Email.deliver_immediate(delivery)
    assert Repo.get!(Delivery, delivery.id).status == :skipped
    refute_email_sent()
  end

  test "domain events only match subscriptions for their classified domains" do
    first = user("first@example.com")
    second = user("second@example.com")
    first_domain_id = Ecto.UUID.generate()
    second_domain_id = Ecto.UUID.generate()

    Notifications.subscribe(first, :domain_drops,
      scope_id: first_domain_id,
      cadence: :immediate
    )

    Notifications.subscribe(second, :domain_drops,
      scope_id: second_domain_id,
      cadence: :immediate
    )

    {:ok, _event} =
      Notifications.publish(%{
        deduplication_key: "drop_published:test",
        type: :drop_published,
        resource_type: "drop",
        resource_id: Ecto.UUID.generate(),
        data: %{"domain_ids" => [first_domain_id]}
      })

    :ok = Notifications.dispatch_pending()

    assert [%Delivery{user_id: user_id}] = Repo.all(Delivery)
    assert user_id == first.id
  end

  test "daily deliveries for one category share one scheduled summary job" do
    actor = user("actor@example.com")
    follower = user("follower@example.com")
    Notifications.subscribe(follower, :forage_new_items, cadence: :daily)

    {:ok, _first} =
      Forage.create_feature_request(
        %{"title" => "First item", "description" => "The first item in a daily summary."},
        actor
      )

    {:ok, _second} =
      Forage.create_feature_request(
        %{"title" => "Second item", "description" => "The second item in a daily summary."},
        actor
      )

    :ok = Notifications.dispatch_pending()

    assert [_job] = all_enqueued(worker: DeliveryWorker)
    assert Repo.aggregate(Delivery, :count) == 2
  end

  test "followers of a Forage item follow a spec created from it" do
    creator = user("creator@example.com")
    follower = user("follower@example.com")

    {:ok, item} =
      Forage.create_feature_request(
        %{
          "title" => "Notification preferences",
          "description" => "Let each person choose which updates should arrive."
        },
        creator
      )

    Notifications.follow_forage_item(follower, "manual:#{item.id}", cadence: :immediate)

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Email notification preferences",
          "body" => "Add durable preferences and authorized email delivery.",
          "source_feature_request_id" => item.id
        },
        creator
      )

    assert Notifications.get_subscription(follower, :spec_updates, spec.id).cadence == :immediate
    assert Notifications.subscribed?(creator, :spec_updates, spec.id)

    assert %Event{resource_id: "manual:" <> item_id} =
             Repo.get_by!(Event, type: :forage_spec_created, resource_id: "manual:#{item.id}")

    assert item_id == item.id
  end

  test "an email about one spec offers to stop only that spec" do
    author = user("author@example.com")
    follower = user("follower@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "Scoped spec", "body" => "The one being discussed."}, author)

    {:ok, other} =
      Specs.create_spec(%{"title" => "Other spec", "body" => "Unrelated proposal."}, author)

    Notifications.follow_spec(follower, spec.id, cadence: :immediate)
    Notifications.follow_spec(follower, other.id, cadence: :immediate)

    Notifications.publish!(%{
      deduplication_key: "spec_updated:#{spec.id}",
      type: :spec_updated,
      resource_type: "spec",
      resource_id: spec.id,
      actor_id: author.id
    })

    :ok = Notifications.dispatch_pending()
    delivery = Repo.get_by!(Delivery, topic: :spec_updates, user_id: follower.id)

    assert :ok = Email.deliver_immediate(delivery)

    assert_email_sent(fn email ->
      assert {:ok, user_id, :spec_updates, scope_id} =
               email |> unsubscribe_token_from() |> Email.verify_unsubscribe_token()

      assert user_id == follower.id
      assert scope_id == spec.id
    end)
  end

  defp unsubscribe_token_from(email) do
    "<" <> rest = Map.fetch!(email.headers, "List-Unsubscribe")

    rest
    |> String.trim_trailing(">")
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
    |> Map.fetch!("token")
  end

  test "delivery skips a resource the subscriber can no longer view" do
    creator = user("creator@example.com")
    follower = user("follower@example.com")

    {:ok, project} =
      Projects.create_project(%{name: "Private notifications", visibility: :private})

    Notifications.subscribe(follower, :spec_new, cadence: :immediate)

    {:ok, _spec} =
      Specs.create_spec(
        %{
          "title" => "Private spec",
          "body" => "This proposal is visible only to organization members.",
          "project_id" => project.id
        },
        creator
      )

    :ok = Notifications.dispatch_pending()
    {:ok, _follower} = Accounts.update_user_role(follower, :collaborator)
    delivery = Repo.one!(Delivery)

    assert :ok = Email.deliver_immediate(delivery)
    assert Repo.get!(Delivery, delivery.id).skip_reason == "unauthorized"
    refute_email_sent()
  end
end

defmodule Hive.Notifications.DeliveryWorkerTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Notifications
  alias Hive.Notifications.Delivery
  alias Hive.Notifications.DeliveryWorker
  alias Hive.Notifications.Email
  alias Hive.Repo

  setup do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "follower@example.com",
        provider: "test",
        provider_uid: "follower@example.com"
      })

    {:ok, event} =
      Notifications.publish(%{
        deduplication_key: "forage_item_created:#{Ecto.UUID.generate()}",
        type: :forage_item_created,
        resource_type: "forage_item",
        resource_id: "manual:#{Ecto.UUID.generate()}"
      })

    delivery =
      Repo.insert!(%Delivery{
        event_id: event.id,
        user_id: user.id,
        topic: :forage_new_items,
        cadence: :immediate,
        status: :pending,
        scheduled_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    %{delivery: delivery}
  end

  test "a delivery that raises on its last attempt stops being retried", %{delivery: delivery} do
    stub(Email, :deliver_immediate, fn _delivery -> raise "the renderer blew up" end)

    assert_raise RuntimeError, "the renderer blew up", fn ->
      DeliveryWorker.perform(job(delivery, 5))
    end

    stored = Repo.get!(Delivery, delivery.id)
    assert stored.status == :failed
    assert stored.last_error =~ "the renderer blew up"
  end

  test "a delivery that raises with attempts left stays pending", %{delivery: delivery} do
    stub(Email, :deliver_immediate, fn _delivery -> raise "a transient failure" end)

    assert_raise RuntimeError, "a transient failure", fn ->
      DeliveryWorker.perform(job(delivery, 1))
    end

    assert Repo.get!(Delivery, delivery.id).status == :pending
  end

  defp job(delivery, attempt) do
    %Oban.Job{
      args: %{"delivery_id" => delivery.id, "cadence" => "immediate"},
      attempt: attempt,
      max_attempts: 5
    }
  end
end

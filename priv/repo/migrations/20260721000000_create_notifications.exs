defmodule Hive.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notification_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :topic, :string, null: false
      add :scope_type, :string, null: false
      add :scope_id, :string, null: false
      add :cadence, :string, null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :notification_subscriptions,
             [:user_id, :topic, :scope_type, :scope_id],
             name: :notification_subscriptions_user_topic_scope_index
           )

    create index(:notification_subscriptions, [:topic, :scope_type, :scope_id])

    create constraint(:notification_subscriptions, :notification_subscriptions_topic_check,
             check:
               "topic IN ('forage_new_items', 'forage_item_updates', 'spec_new', 'spec_updates', 'domain_drops', 'weekly_drop_digest')"
           )

    create constraint(:notification_subscriptions, :notification_subscriptions_scope_type_check,
             check: "scope_type IN ('global', 'domain', 'forage_item', 'spec')"
           )

    create constraint(:notification_subscriptions, :notification_subscriptions_cadence_check,
             check: "cadence IN ('immediate', 'daily')"
           )

    create constraint(:notification_subscriptions, :notification_subscriptions_scope_check,
             check: """
             (topic IN ('forage_new_items', 'spec_new', 'weekly_drop_digest') AND scope_type = 'global' AND scope_id = 'global') OR
             (topic = 'forage_item_updates' AND scope_type = 'forage_item') OR
             (topic = 'spec_updates' AND scope_type = 'spec') OR
             (topic = 'domain_drops' AND scope_type = 'domain')
             """
           )

    create table(:notification_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :deduplication_key, :string, null: false
      add :type, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :string, null: false
      add :data, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime, null: false
      add :dispatched_at, :utc_datetime

      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:notification_events, [:deduplication_key])
    create index(:notification_events, [:dispatched_at, :occurred_at])

    create constraint(:notification_events, :notification_events_type_check,
             check:
               "type IN ('forage_item_created', 'forage_item_updated', 'forage_comment_created', 'forage_spec_created', 'forage_flight_completed', 'spec_created', 'spec_updated', 'spec_comment_created', 'spec_review_requested', 'drop_published', 'weekly_drop_digest_published')"
           )

    create table(:notification_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :topic, :string, null: false
      add :cadence, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :scheduled_at, :utc_datetime, null: false
      add :sent_at, :utc_datetime
      add :provider_message_id, :string
      add :skip_reason, :string
      add :last_error, :string

      add :event_id, references(:notification_events, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:notification_deliveries, [:event_id, :user_id, :topic])
    create index(:notification_deliveries, [:status, :scheduled_at])
    create index(:notification_deliveries, [:user_id, :topic, :cadence, :status])

    create constraint(:notification_deliveries, :notification_deliveries_status_check,
             check: "status IN ('pending', 'sent', 'skipped', 'failed')"
           )
  end
end

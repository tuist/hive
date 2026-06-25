defmodule Hive.Repo.Migrations.CreateSlackNotificationRoutes do
  use Ecto.Migration

  def change do
    create table(:slack_notification_routes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :installation_id,
          references(:slack_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :object_type, :string, null: false
      add :slack_channel_id, :string, null: false
      add :notification_events, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:slack_notification_routes, [:installation_id, :object_type])
  end
end

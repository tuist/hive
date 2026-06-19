defmodule Hive.Repo.Migrations.AddNotificationsToSlackInstallations do
  use Ecto.Migration

  def change do
    alter table(:slack_installations) do
      add :notification_channel_id, :string
      add :notification_events, {:array, :string}, null: false, default: []
    end
  end
end

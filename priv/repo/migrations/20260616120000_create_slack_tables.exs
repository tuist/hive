defmodule Hive.Repo.Migrations.CreateSlackTables do
  use Ecto.Migration

  def change do
    create table(:slack_installations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :team_id, :string, null: false
      add :team_name, :string
      add :bot_user_id, :string
      add :bot_token, :string
      add :scope, :text
      add :installed_at, :utc_datetime
      add :disconnected_at, :utc_datetime
      add :installed_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:slack_installations, [:team_id])
    create index(:slack_installations, [:installed_by_user_id])

    create table(:slack_channels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :installation_id,
          references(:slack_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :slack_channel_id, :string, null: false
      add :name, :string
      add :is_private, :boolean, null: false, default: false
      add :is_archived, :boolean, null: false, default: false
      add :topic, :text
      add :purpose, :text
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:slack_channels, [:installation_id, :slack_channel_id])

    create table(:slack_users, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :installation_id,
          references(:slack_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :slack_user_id, :string, null: false
      add :email, :string
      add :name, :string
      add :real_name, :string
      add :is_bot, :boolean, null: false, default: false
      add :deleted, :boolean, null: false, default: false
      add :linked_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:slack_users, [:installation_id, :slack_user_id])
    create index(:slack_users, [:linked_user_id])
    create index(:slack_users, [:email])

    create table(:slack_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :installation_id,
          references(:slack_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :channel_id, references(:slack_channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :slack_user_id, :string
      add :slack_ts, :string, null: false
      add :thread_ts, :string
      add :text, :text
      add :raw_payload, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:slack_messages, [:channel_id, :slack_ts])
    create index(:slack_messages, [:installation_id])
    create index(:slack_messages, [:thread_ts])
  end
end

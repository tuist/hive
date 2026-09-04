defmodule Hive.Repo.Migrations.AddWebhookDestinationToAlerts do
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :destination_type, :string, size: 16, null: false, default: "slack"
      add :webhook_url, :text
      add :webhook_signing_secret, :string, size: 128
    end

    create index(:alert_rules, [:destination_type])
  end
end

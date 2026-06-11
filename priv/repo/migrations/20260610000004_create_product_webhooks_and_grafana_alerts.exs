defmodule Hive.Repo.Migrations.CreateProductWebhooksAndGrafanaAlerts do
  use Ecto.Migration

  def change do
    create table(:product_webhooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :source, :string, null: false
      add :token_hash, :string, null: false

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        null: false

      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:product_webhooks, [:token_hash])
    create index(:product_webhooks, [:product_id])

    create table(:forage_grafana_alerts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :fingerprint, :string, null: false
      add :status, :string, null: false
      add :title, :string, null: false
      add :summary, :text
      add :generator_url, :text
      add :labels, :map, null: false, default: %{}
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :last_received_at, :utc_datetime, null: false

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        null: false

      add :webhook_id, references(:product_webhooks, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:forage_grafana_alerts, [:product_id, :fingerprint])
    create index(:forage_grafana_alerts, [:status])
    create index(:forage_grafana_alerts, [:last_received_at])
  end
end

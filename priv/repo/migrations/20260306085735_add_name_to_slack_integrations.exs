defmodule Hive.Repo.Migrations.AddNameToSlackIntegrations do
  use Ecto.Migration

  def change do
    alter table(:slack_integrations) do
      add :name, :string, null: false, default: "Slack Bot"
    end
  end
end

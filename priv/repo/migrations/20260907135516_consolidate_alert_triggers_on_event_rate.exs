defmodule Hive.Repo.Migrations.ConsolidateAlertTriggersOnEventRate do
  use Ecto.Migration

  def up do
    execute("UPDATE alert_rules SET trigger = 'event_rate' WHERE trigger = 'new_issue_threshold'")

    alter table(:alert_rules) do
      remove :threshold_window_minutes
    end
  end

  def down do
    alter table(:alert_rules) do
      add :threshold_window_minutes, :integer
    end

    execute("UPDATE alert_rules SET threshold_window_minutes = 60 WHERE trigger = 'event_rate'")
  end
end

defmodule Hive.Repo.Migrations.WidenAuditTargetLabelToText do
  use Ecto.Migration

  def up do
    alter table(:audit_activities) do
      modify :target_label, :text
    end
  end

  def down do
    alter table(:audit_activities) do
      modify :target_label, :string
    end
  end
end

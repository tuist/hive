defmodule Hive.Repo.Migrations.AddActorKindToAuditActivities do
  use Ecto.Migration

  def change do
    alter table(:audit_activities) do
      add :actor_kind, :string, null: false, default: "system"
    end

    execute(
      "UPDATE audit_activities SET actor_kind = 'user' WHERE actor_id IS NOT NULL",
      ""
    )

    create index(:audit_activities, [:actor_kind, :occurred_at])
  end
end

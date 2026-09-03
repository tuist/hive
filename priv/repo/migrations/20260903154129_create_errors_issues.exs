defmodule Hive.Repo.Migrations.CreateErrorsIssues do
  use Ecto.Migration

  def change do
    create table(:errors_issues, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :fingerprint, :string, size: 64, null: false
      add :title, :text, null: false
      add :culprit, :text
      add :level, :string, size: 16, null: false, default: "error"
      add :platform, :string, size: 32
      add :status, :string, size: 16, null: false, default: "unresolved"
      add :first_seen, :utc_datetime_usec, null: false
      add :last_seen, :utc_datetime_usec, null: false
      add :event_count, :bigint, null: false, default: 0
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:errors_issues, [:project_id, :fingerprint])
    create index(:errors_issues, [:project_id, :status, :last_seen])
    create index(:errors_issues, [:assignee_id])
  end
end

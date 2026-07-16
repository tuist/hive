defmodule Hive.Repo.Migrations.CreateForageCodingRuns do
  use Ecto.Migration

  def change do
    create table(:forage_coding_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :forage_item_id, :string, null: false
      add :status, :string, null: false
      add :runner, :string, null: false
      add :runner_id, :string
      add :repository_full_name, :string, null: false
      add :input, :map, null: false, default: %{}
      add :result, :map
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      add :repository_id,
          references(:github_repositories, type: :binary_id, on_delete: :nilify_all)

      add :requested_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:forage_coding_runs, [:forage_item_id, :inserted_at])
    create index(:forage_coding_runs, [:repository_id])
    create index(:forage_coding_runs, [:requested_by_id])

    create unique_index(:forage_coding_runs, [:forage_item_id, :repository_id],
             name: :forage_coding_runs_one_active_run,
             where: "status IN ('queued', 'running')"
           )
  end
end

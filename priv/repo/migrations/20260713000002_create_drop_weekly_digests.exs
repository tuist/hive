defmodule Hive.Repo.Migrations.CreateDropWeeklyDigests do
  use Ecto.Migration

  def change do
    create table(:drop_weekly_digests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :week_start, :date, null: false
      add :week_end, :date, null: false
      add :status, :string, null: false
      add :title, :string
      add :summary, :text
      add :body, :text
      add :drop_ids, {:array, :uuid}, null: false, default: []
      add :published_at, :utc_datetime
      add :failure_reason, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:drop_weekly_digests, [:week_start])
    create index(:drop_weekly_digests, [:status, :published_at])
  end
end

defmodule Hive.Repo.Migrations.AddReleaseIngestionRetryState do
  use Ecto.Migration

  def change do
    alter table(:drop_github_release_ingestions) do
      add :attempt_count, :integer, null: false, default: 0
      add :last_error, :text
      add :next_attempt_at, :utc_datetime
    end

    create index(:drop_github_release_ingestions, [:status, :next_attempt_at])
  end
end

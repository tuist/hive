defmodule Hive.Repo.Migrations.AddResolvedAtToErrorsIssues do
  use Ecto.Migration

  def change do
    alter table(:errors_issues) do
      add :resolved_at, :utc_datetime_usec
    end
  end
end

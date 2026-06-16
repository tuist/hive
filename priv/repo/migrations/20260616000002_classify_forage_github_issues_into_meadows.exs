defmodule Hive.Repo.Migrations.ClassifyForageGithubIssuesIntoMeadows do
  use Ecto.Migration

  def change do
    alter table(:forage_github_issues) do
      add :classified_at, :utc_datetime
    end

    create table(:forage_github_issue_meadows, primary_key: false) do
      add :forage_github_issue_id,
          references(:forage_github_issues, type: :binary_id, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :meadow_id,
          references(:meadows, type: :binary_id, on_delete: :delete_all),
          null: false,
          primary_key: true

      timestamps(type: :utc_datetime)
    end

    create index(:forage_github_issue_meadows, [:meadow_id])
  end
end

defmodule Hive.Repo.Migrations.CreateDropGithubIssues do
  use Ecto.Migration

  def change do
    create table(:drop_github_issues, primary_key: false) do
      add :drop_id, references(:drops, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :forage_github_issue_id,
          references(:forage_github_issues, type: :binary_id, on_delete: :delete_all),
          null: false,
          primary_key: true

      timestamps(type: :utc_datetime)
    end

    create index(:drop_github_issues, [:forage_github_issue_id])
  end
end

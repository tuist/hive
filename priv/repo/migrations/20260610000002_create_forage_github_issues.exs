defmodule Hive.Repo.Migrations.CreateForageGithubIssues do
  use Ecto.Migration

  def change do
    create table(:forage_github_issues, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :github_repository_id,
          references(:github_repositories, type: :binary_id, on_delete: :delete_all),
          null: false

      add :number, :integer, null: false
      add :title, :string, null: false, size: 500
      add :body, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:forage_github_issues, [:github_repository_id, :number])
  end
end

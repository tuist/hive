defmodule Hive.Repo.Migrations.CreateDropGithubReleaseIngestions do
  use Ecto.Migration

  def change do
    create table(:drop_github_release_ingestions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :github_repository_id,
          references(:github_repositories, type: :binary_id, on_delete: :delete_all),
          null: false

      add :release_key, :text, null: false
      add :release_key_hash, :string, null: false
      add :release_fingerprint, :string, null: false
      add :status, :string, null: false
      add :items_count, :integer, null: false, default: 0
      add :processed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :drop_github_release_ingestions,
             [
               :github_repository_id,
               :release_key_hash
             ], name: :drop_release_ingestions_repo_key_index)

    create index(:drop_github_release_ingestions, [:github_repository_id])
    create index(:drop_github_release_ingestions, [:status])
  end
end

defmodule Hive.Repo.Migrations.AddVisibilityToGithubRepositories do
  use Ecto.Migration

  def change do
    alter table(:github_repositories) do
      add :visibility, :string, null: false, default: "public"
    end

    create constraint(:github_repositories, :github_repositories_visibility_check,
             check: "visibility in ('public', 'private')"
           )

    create index(:github_repositories, [:visibility])
  end
end

defmodule Hive.Repo.Migrations.AddStateToForageGithubIssues do
  use Ecto.Migration

  def change do
    alter table(:forage_github_issues) do
      add :state, :string, null: false, default: "open"
    end

    create constraint(:forage_github_issues, :forage_github_issues_state_check,
             check: "state in ('open', 'closed')"
           )

    create index(:forage_github_issues, [:state])
  end
end

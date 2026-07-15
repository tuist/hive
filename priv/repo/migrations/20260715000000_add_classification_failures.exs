defmodule Hive.Repo.Migrations.AddClassificationFailures do
  use Ecto.Migration

  def change do
    alter table(:drops) do
      add :classification_failure, :string
      add :classification_failed_at, :utc_datetime
    end

    alter table(:forage_github_issues) do
      add :classification_failure, :string
      add :classification_failed_at, :utc_datetime
    end

    create index(:drops, [:inserted_at],
             where: "classified_at IS NULL AND classification_failed_at IS NULL",
             name: :drops_pending_classification_index
           )

    create index(:forage_github_issues, [:inserted_at],
             where: "classified_at IS NULL AND classification_failed_at IS NULL",
             name: :forage_github_issues_pending_classification_index
           )
  end
end

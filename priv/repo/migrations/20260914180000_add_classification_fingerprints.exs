defmodule Hive.Repo.Migrations.AddClassificationFingerprints do
  use Ecto.Migration

  def change do
    alter table(:forage_github_issues) do
      add :classification_fingerprint, :string
    end

    alter table(:drops) do
      add :classification_fingerprint, :string
    end
  end
end

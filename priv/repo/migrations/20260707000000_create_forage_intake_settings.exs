defmodule Hive.Repo.Migrations.CreateForageIntakeSettings do
  use Ecto.Migration

  def change do
    create table(:forage_intake_settings, primary_key: false) do
      add :id, :text, primary_key: true
      add :destination, :text, null: false, default: "hive_item"

      add :github_repository_id,
          references(:github_repositories, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create constraint(:forage_intake_settings, :forage_intake_settings_destination_check,
             check: "destination IN ('hive_item', 'github_issue')"
           )

    create index(:forage_intake_settings, [:github_repository_id])
  end
end

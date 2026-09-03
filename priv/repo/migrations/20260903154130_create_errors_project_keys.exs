defmodule Hive.Repo.Migrations.CreateErrorsProjectKeys do
  use Ecto.Migration

  def change do
    create table(:errors_project_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :public_key, :string, size: 32, null: false
      add :secret_key, :string, size: 32
      add :name, :string, null: false, default: "default"
      add :last_used_at, :utc_datetime_usec
      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:errors_project_keys, [:public_key])
    create index(:errors_project_keys, [:project_id])
  end
end

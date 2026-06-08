defmodule Hive.Repo.Migrations.CreateSpecs do
  use Ecto.Migration

  def change do
    create table(:specs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :text, null: false, default: "draft"
      add :lock_version, :integer, null: false, default: 1

      add :source_feature_request_id,
          references(:forage_feature_requests, type: :binary_id, on_delete: :nilify_all)

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :updated_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:specs, [:status])
    create index(:specs, [:source_feature_request_id])
    create index(:specs, [:created_by_user_id])

    create table(:spec_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false
      add :author_name, :string
      add :spec_id, references(:specs, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:spec_comments, [:spec_id])
    create index(:spec_comments, [:user_id])
  end
end

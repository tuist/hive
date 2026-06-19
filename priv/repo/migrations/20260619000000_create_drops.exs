defmodule Hive.Repo.Migrations.CreateDrops do
  use Ecto.Migration

  def change do
    create table(:drop_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :url, :text, null: false
      add :label, :string
      add :enabled, :boolean, null: false, default: true
      add :last_polled_at, :utc_datetime
      add :last_error, :text
      add :last_error_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:drop_sources, [:url])
    create index(:drop_sources, [:enabled])

    create table(:drops, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_type, :string, null: false
      add :external_id, :string, null: false
      add :title, :string, null: false
      add :body, :text
      add :raw_body, :text
      add :rewritten_at, :utc_datetime
      add :url, :text, null: false
      add :version, :string
      add :published_at, :utc_datetime
      add :classified_at, :utc_datetime

      add :drop_source_id,
          references(:drop_sources, type: :binary_id, on_delete: :delete_all)

      add :github_repository_id,
          references(:github_repositories, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:drops, [:source_type, :external_id])
    create index(:drops, [:published_at])
    create index(:drops, [:drop_source_id])
    create index(:drops, [:github_repository_id])
    create index(:drops, [:classified_at])

    create table(:drop_meadows, primary_key: false) do
      add :drop_id, references(:drops, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :meadow_id, references(:meadows, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      timestamps(type: :utc_datetime)
    end

    create index(:drop_meadows, [:meadow_id])
  end
end

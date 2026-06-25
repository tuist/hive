defmodule Hive.Repo.Migrations.CreateInferenceRelay do
  use Ecto.Migration

  def change do
    create table(:inference_model_bindings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :upstream_provider, :string, null: false
      add :upstream_model, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:inference_model_bindings, [:name])
    create index(:inference_model_bindings, [:enabled])

    create table(:inference_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token_hash, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :expires_at, :utc_datetime
      add :last_used_at, :utc_datetime

      add :model_binding_id,
          references(:inference_model_bindings, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:inference_tokens, [:token_hash])
    create index(:inference_tokens, [:model_binding_id])
    create index(:inference_tokens, [:enabled])
  end
end

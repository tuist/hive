defmodule Hive.Repo.Migrations.CreateInferenceUsage do
  use Ecto.Migration

  def change do
    create table(:inference_usages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :upstream_provider, :string, null: false
      add :upstream_model, :string, null: false
      add :status, :integer, null: false
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :total_tokens, :integer, null: false, default: 0
      add :cost_usd, :decimal, precision: 18, scale: 9, null: false, default: 0

      add :model_binding_id,
          references(:inference_model_bindings, type: :binary_id, on_delete: :delete_all),
          null: false

      add :token_id,
          references(:inference_tokens, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:inference_usages, [:model_binding_id, :inserted_at])
    create index(:inference_usages, [:token_id, :inserted_at])
  end
end

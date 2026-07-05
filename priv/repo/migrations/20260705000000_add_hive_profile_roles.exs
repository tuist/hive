defmodule Hive.Repo.Migrations.AddHiveProfileRoles do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    alter table(:inference_model_bindings) do
      add :hive_inference, :boolean, null: false, default: false
      add :hive_embedding, :boolean, null: false, default: false
    end

    create unique_index(:inference_model_bindings, [:hive_inference],
             where: "hive_inference",
             concurrently: true,
             name: :inference_model_bindings_single_hive_inference_index
           )

    create unique_index(:inference_model_bindings, [:hive_embedding],
             where: "hive_embedding",
             concurrently: true,
             name: :inference_model_bindings_single_hive_embedding_index
           )

    alter table(:inference_tokens) do
      add :hive_role, :string
      add :token_ciphertext, :text
    end

    create unique_index(:inference_tokens, [:model_binding_id, :hive_role],
             where: "hive_role IS NOT NULL",
             concurrently: true,
             name: :inference_tokens_model_binding_hive_role_index
           )
  end
end

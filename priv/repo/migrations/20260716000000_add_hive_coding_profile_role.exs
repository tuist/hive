defmodule Hive.Repo.Migrations.AddHiveCodingProfileRole do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    alter table(:inference_model_bindings) do
      add :hive_coding, :boolean, null: false, default: false
    end

    create unique_index(:inference_model_bindings, [:hive_coding],
             where: "hive_coding",
             concurrently: true,
             name: :inference_model_bindings_single_hive_coding_index
           )
  end
end

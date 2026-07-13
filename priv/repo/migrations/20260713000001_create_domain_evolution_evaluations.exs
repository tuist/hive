defmodule Hive.Repo.Migrations.CreateDomainEvolutionEvaluations do
  use Ecto.Migration

  def change do
    create table(:domain_evolution_evaluations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :fingerprint, :string, null: false
      add :outcome, :string, null: false
      add :work_items_count, :integer, null: false
      add :created_count, :integer, null: false
      add :updated_count, :integer, null: false
      add :skipped_count, :integer, null: false
      add :evaluated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:domain_evolution_evaluations, [:fingerprint])
  end
end

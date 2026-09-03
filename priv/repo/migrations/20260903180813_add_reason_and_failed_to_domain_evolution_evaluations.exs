defmodule Hive.Repo.Migrations.AddReasonAndFailedToDomainEvolutionEvaluations do
  use Ecto.Migration

  def change do
    alter table(:domain_evolution_evaluations) do
      add :reason, :string
    end
  end
end

defmodule Hive.Repo.Migrations.AddInferenceProfilePricing do
  use Ecto.Migration

  def change do
    alter table(:inference_model_bindings) do
      add :input_cost_per_million, :decimal, precision: 18, scale: 9
      add :output_cost_per_million, :decimal, precision: 18, scale: 9
    end
  end
end

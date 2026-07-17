defmodule Hive.Repo.Migrations.AddFlightObjectivesAndTriggers do
  use Ecto.Migration

  def change do
    alter table(:flights) do
      add :objective, :string, null: false, default: "investigate"
      add :objective_outcome, :string
      add :trigger, :map, null: false, default: %{}
      add :parent_flight_id, references(:flights, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:flights, [:objective])
    create index(:flights, [:objective_outcome])
    create index(:flights, [:parent_flight_id])
  end
end

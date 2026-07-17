defmodule Hive.Repo.Migrations.BackfillExistingFlightObjectives do
  use Ecto.Migration

  def up do
    execute """
    UPDATE flights
    SET objective = 'fix'
    WHERE objective = 'investigate' AND trigger = '{}'::jsonb
    """
  end

  def down do
    :ok
  end
end

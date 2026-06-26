defmodule Hive.Repo.Migrations.AddNumberToDrops do
  use Ecto.Migration

  def up do
    alter table(:drops) do
      add :number, :bigint
    end

    execute """
    WITH numbered AS (
      SELECT id, row_number() OVER (ORDER BY inserted_at, id) AS number
      FROM drops
    )
    UPDATE drops
    SET number = numbered.number
    FROM numbered
    WHERE drops.id = numbered.id
    """

    alter table(:drops) do
      modify :number, :bigint, null: false
    end

    create unique_index(:drops, [:number])
  end

  def down do
    drop_if_exists unique_index(:drops, [:number])

    alter table(:drops) do
      remove :number
    end
  end
end

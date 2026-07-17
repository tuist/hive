defmodule Hive.Repo.Migrations.PromoteCodingRunsToFlights do
  use Ecto.Migration

  def up do
    rename table(:forage_coding_runs), to: table(:flights)

    alter table(:flights) do
      add :session, :map
    end

    execute "ALTER INDEX forage_coding_runs_pkey RENAME TO flights_pkey"

    execute "ALTER INDEX forage_coding_runs_forage_item_id_inserted_at_index RENAME TO flights_forage_item_id_inserted_at_index"

    execute "ALTER INDEX forage_coding_runs_repository_id_index RENAME TO flights_repository_id_index"

    execute "ALTER INDEX forage_coding_runs_requested_by_id_index RENAME TO flights_requested_by_id_index"

    execute "ALTER INDEX forage_coding_runs_one_active_run RENAME TO flights_one_active_run"
  end

  def down do
    execute "ALTER INDEX flights_one_active_run RENAME TO forage_coding_runs_one_active_run"

    execute "ALTER INDEX flights_requested_by_id_index RENAME TO forage_coding_runs_requested_by_id_index"

    execute "ALTER INDEX flights_repository_id_index RENAME TO forage_coding_runs_repository_id_index"

    execute "ALTER INDEX flights_forage_item_id_inserted_at_index RENAME TO forage_coding_runs_forage_item_id_inserted_at_index"

    execute "ALTER INDEX flights_pkey RENAME TO forage_coding_runs_pkey"

    alter table(:flights) do
      remove :session
    end

    rename table(:flights), to: table(:forage_coding_runs)
  end
end

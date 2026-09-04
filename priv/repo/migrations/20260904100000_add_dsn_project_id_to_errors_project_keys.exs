defmodule Hive.Repo.Migrations.AddDsnProjectIdToErrorsProjectKeys do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE errors_project_keys_dsn_project_id_seq"

    alter table(:errors_project_keys) do
      add :dsn_project_id, :bigint
    end

    execute """
    UPDATE errors_project_keys
    SET dsn_project_id = nextval('errors_project_keys_dsn_project_id_seq')
    """

    alter table(:errors_project_keys) do
      modify :dsn_project_id, :bigint,
        null: false,
        default: fragment("nextval('errors_project_keys_dsn_project_id_seq')")
    end

    create unique_index(:errors_project_keys, [:dsn_project_id])
  end

  def down do
    drop_if_exists unique_index(:errors_project_keys, [:dsn_project_id])

    alter table(:errors_project_keys) do
      remove :dsn_project_id
    end

    execute "DROP SEQUENCE errors_project_keys_dsn_project_id_seq"
  end
end

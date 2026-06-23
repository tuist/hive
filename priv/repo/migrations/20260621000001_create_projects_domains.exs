defmodule Hive.Repo.Migrations.CreateProjectsDomains do
  use Ecto.Migration

  def up do
    create table(:projects_domains, primary_key: false) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :domain_id, references(:domains, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      timestamps(type: :utc_datetime)
    end

    create index(:projects_domains, [:domain_id])

    flush()

    execute """
    INSERT INTO projects_domains (project_id, domain_id, inserted_at, updated_at)
    SELECT project_id, id, now(), now()
    FROM domains
    WHERE project_id IS NOT NULL
    ON CONFLICT DO NOTHING
    """

    drop index(:domains, [:project_id])

    alter table(:domains) do
      remove :project_id
    end
  end

  def down do
    alter table(:domains) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)
    end

    create index(:domains, [:project_id])

    flush()

    execute """
    UPDATE domains
    SET project_id = link.project_id
    FROM (
      SELECT DISTINCT ON (domain_id) domain_id, project_id
      FROM projects_domains
      ORDER BY domain_id, inserted_at ASC
    ) AS link
    WHERE link.domain_id = domains.id
    """

    drop table(:projects_domains)
  end
end

defmodule Hive.Repo.Migrations.MoveWebhooksToProjects do
  use Ecto.Migration

  def up do
    rename table(:domain_webhooks), to: table(:project_webhooks)

    alter table(:project_webhooks) do
      add :project_id_tmp, references(:projects, type: :binary_id, on_delete: :delete_all)
    end

    execute """
    UPDATE project_webhooks
    SET project_id_tmp = link.project_id
    FROM (
      SELECT DISTINCT ON (domain_id) domain_id, project_id
      FROM projects_domains
      ORDER BY domain_id, inserted_at ASC
    ) AS link
    WHERE link.domain_id = project_webhooks.domain_id
    """

    execute "DELETE FROM project_webhooks WHERE project_id_tmp IS NULL"

    drop_if_exists index(:project_webhooks, [:domain_id], name: :domain_webhooks_domain_id_index)

    alter table(:project_webhooks) do
      remove :domain_id
      modify :project_id_tmp, :binary_id, null: false
    end

    rename table(:project_webhooks), :project_id_tmp, to: :project_id

    execute "ALTER INDEX domain_webhooks_pkey RENAME TO project_webhooks_pkey"

    execute "ALTER INDEX domain_webhooks_token_hash_index RENAME TO project_webhooks_token_hash_index"

    create index(:project_webhooks, [:project_id])

    alter table(:forage_grafana_alerts) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)
    end

    execute """
    UPDATE forage_grafana_alerts
    SET project_id = link.project_id
    FROM (
      SELECT DISTINCT ON (domain_id) domain_id, project_id
      FROM projects_domains
      ORDER BY domain_id, inserted_at ASC
    ) AS link
    WHERE link.domain_id = forage_grafana_alerts.domain_id
    """

    execute "DELETE FROM forage_grafana_alerts WHERE project_id IS NULL"

    drop_if_exists index(:forage_grafana_alerts, [:domain_id, :fingerprint],
                     name: :forage_grafana_alerts_domain_id_fingerprint_index
                   )

    alter table(:forage_grafana_alerts) do
      modify :project_id, :binary_id, null: false
      modify :domain_id, :binary_id, null: true
    end

    create unique_index(:forage_grafana_alerts, [:project_id, :fingerprint])
    create index(:forage_grafana_alerts, [:domain_id])
  end

  def down do
    drop_if_exists index(:forage_grafana_alerts, [:domain_id])
    drop_if_exists index(:forage_grafana_alerts, [:project_id, :fingerprint])

    execute """
    UPDATE forage_grafana_alerts
    SET domain_id = link.domain_id
    FROM (
      SELECT DISTINCT ON (project_id) project_id, domain_id
      FROM projects_domains
      ORDER BY project_id, inserted_at ASC
    ) AS link
    WHERE link.project_id = forage_grafana_alerts.project_id
      AND forage_grafana_alerts.domain_id IS NULL
    """

    execute "DELETE FROM forage_grafana_alerts WHERE domain_id IS NULL"

    alter table(:forage_grafana_alerts) do
      modify :domain_id, :binary_id, null: false
      remove :project_id
    end

    execute "ALTER INDEX project_webhooks_token_hash_index RENAME TO domain_webhooks_token_hash_index"
    execute "ALTER INDEX project_webhooks_pkey RENAME TO domain_webhooks_pkey"

    alter table(:project_webhooks) do
      add :domain_id_tmp, references(:domains, type: :binary_id, on_delete: :delete_all)
    end

    execute """
    UPDATE project_webhooks
    SET domain_id_tmp = link.domain_id
    FROM (
      SELECT DISTINCT ON (project_id) project_id, domain_id
      FROM projects_domains
      ORDER BY project_id, inserted_at ASC
    ) AS link
    WHERE link.project_id = project_webhooks.project_id
    """

    execute "DELETE FROM project_webhooks WHERE domain_id_tmp IS NULL"

    drop_if_exists index(:project_webhooks, [:project_id])

    alter table(:project_webhooks) do
      remove :project_id
      modify :domain_id_tmp, :binary_id, null: false
    end

    rename table(:project_webhooks), :domain_id_tmp, to: :domain_id
    rename table(:project_webhooks), to: table(:domain_webhooks)

    create index(:domain_webhooks, [:domain_id])
    create unique_index(:forage_grafana_alerts, [:domain_id, :fingerprint])
  end
end

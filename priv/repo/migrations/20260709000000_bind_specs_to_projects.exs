defmodule Hive.Repo.Migrations.BindSpecsToProjects do
  use Ecto.Migration

  def up do
    alter table(:specs) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict)
      add :visibility_override, :string
    end

    create index(:specs, [:project_id])

    create constraint(:specs, :specs_visibility_override_check,
             check: "visibility_override IS NULL OR visibility_override = 'private'"
           )

    flush()

    execute """
    UPDATE specs
    SET visibility_override = 'private'
    WHERE visibility = 'private'
    """

    execute """
    UPDATE specs
    SET project_id = candidate_projects.project_id
    FROM (
      SELECT domains_specs.spec_id, (array_agg(DISTINCT projects_domains.project_id))[1] AS project_id
      FROM domains_specs
      INNER JOIN projects_domains ON projects_domains.domain_id = domains_specs.domain_id
      GROUP BY domains_specs.spec_id
      HAVING count(DISTINCT projects_domains.project_id) = 1
    ) AS candidate_projects
    WHERE candidate_projects.spec_id = specs.id
    """

    execute """
    UPDATE specs
    SET project_id = (SELECT id FROM projects LIMIT 1)
    WHERE project_id IS NULL
      AND (SELECT count(*) FROM projects) = 1
    """

    execute """
    INSERT INTO projects (id, name, description, visibility, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      'Default project',
      NULL,
      'public',
      NOW() AT TIME ZONE 'UTC',
      NOW() AT TIME ZONE 'UTC'
    WHERE EXISTS (SELECT 1 FROM specs WHERE project_id IS NULL)
      AND NOT EXISTS (SELECT 1 FROM projects WHERE name = 'Default project')
    """

    execute """
    UPDATE specs
    SET project_id = (SELECT id FROM projects WHERE name = 'Default project')
    WHERE project_id IS NULL
    """

    execute "ALTER TABLE specs ALTER COLUMN project_id SET NOT NULL"

    drop_if_exists index(:specs, [:visibility])
    drop constraint(:specs, :specs_visibility_check)

    alter table(:specs) do
      remove :visibility
    end
  end

  def down do
    alter table(:specs) do
      add :visibility, :string, null: false, default: "public"
    end

    create constraint(:specs, :specs_visibility_check,
             check: "visibility in ('public', 'private')"
           )

    create index(:specs, [:visibility])

    flush()

    execute """
    UPDATE specs
    SET visibility = 'private'
    FROM projects
    WHERE specs.project_id = projects.id
      AND (specs.visibility_override = 'private' OR projects.visibility = 'private')
    """

    execute """
    UPDATE specs
    SET visibility = 'private'
    WHERE visibility_override = 'private'
      AND project_id IS NULL
    """

    drop constraint(:specs, :specs_visibility_override_check)
    drop index(:specs, [:project_id])

    alter table(:specs) do
      remove :visibility_override
      remove :project_id
    end
  end
end

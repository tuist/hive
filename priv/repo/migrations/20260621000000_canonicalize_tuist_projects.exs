defmodule Hive.Repo.Migrations.CanonicalizeTuistProjects do
  use Ecto.Migration

  def up do
    execute("""
    WITH domain_targets(domain_name, project_name) AS (
      VALUES
        ('Atlas', 'Atlas'),
        ('Hive', 'Hive'),
        ('Tuist', 'Tuist'),
        ('CLI', 'Tuist'),
        ('Cache', 'Tuist'),
        ('Compute', 'Tuist'),
        ('Distribution', 'Tuist'),
        ('Generated projects', 'Tuist'),
        ('Kura', 'Kura'),
        ('Noora', 'Noora'),
        ('Once', 'Once')
    )
    UPDATE domains AS domain
    SET project_id = project.id,
        updated_at = NOW() AT TIME ZONE 'UTC'
    FROM domain_targets AS target
    JOIN projects AS project ON project.name = target.project_name
    WHERE domain.name = target.domain_name
      AND domain.project_id IS DISTINCT FROM project.id
    """)

    execute("""
    WITH project_targets(legacy_name, project_name) AS (
      VALUES
        ('Atlas', 'Atlas'),
        ('Hive', 'Hive'),
        ('Tuist', 'Tuist'),
        ('CLI', 'Tuist'),
        ('Cache', 'Tuist'),
        ('Compute', 'Tuist'),
        ('Distribution', 'Tuist'),
        ('Generated projects', 'Tuist'),
        ('Kura', 'Kura'),
        ('Noora', 'Noora'),
        ('Once', 'Once')
    )
    UPDATE github_repositories AS repository
    SET project_id = project.id,
        updated_at = NOW() AT TIME ZONE 'UTC'
    FROM projects AS legacy
    JOIN project_targets AS target ON target.legacy_name = legacy.name
    JOIN projects AS project ON project.name = target.project_name
    WHERE repository.project_id = legacy.id
      AND repository.project_id IS DISTINCT FROM project.id
    """)

    execute("""
    WITH repository_targets(owner, repository_name, project_name) AS (
      VALUES
        ('tuist', 'atlas', 'Atlas'),
        ('tuist', 'hive', 'Hive'),
        ('tuist', 'tuist', 'Tuist'),
        ('tuist', 'kura', 'Kura'),
        ('tuist', 'noora', 'Noora'),
        ('tuist', 'once', 'Once')
    )
    UPDATE github_repositories AS repository
    SET project_id = project.id,
        updated_at = NOW() AT TIME ZONE 'UTC'
    FROM repository_targets AS target
    JOIN projects AS project ON project.name = target.project_name
    WHERE repository.owner = target.owner
      AND repository.name = target.repository_name
      AND repository.project_id IS DISTINCT FROM project.id
    """)

    execute("""
    WITH project_targets(legacy_name, project_name) AS (
      VALUES
        ('Atlas', 'Atlas'),
        ('Hive', 'Hive'),
        ('Tuist', 'Tuist'),
        ('CLI', 'Tuist'),
        ('Cache', 'Tuist'),
        ('Compute', 'Tuist'),
        ('Distribution', 'Tuist'),
        ('Generated projects', 'Tuist'),
        ('Kura', 'Kura'),
        ('Noora', 'Noora'),
        ('Once', 'Once')
    )
    UPDATE drop_sources AS source
    SET project_id = project.id,
        updated_at = NOW() AT TIME ZONE 'UTC'
    FROM projects AS legacy
    JOIN project_targets AS target ON target.legacy_name = legacy.name
    JOIN projects AS project ON project.name = target.project_name
    WHERE source.project_id = legacy.id
      AND source.project_id IS DISTINCT FROM project.id
    """)

    execute("""
    DELETE FROM projects AS project
    WHERE project.name IN ('CLI', 'Cache', 'Compute', 'Distribution', 'Generated projects')
      AND NOT EXISTS (
        SELECT 1 FROM domains AS domain WHERE domain.project_id = project.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM github_repositories AS repository WHERE repository.project_id = project.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM drop_sources AS source WHERE source.project_id = project.id
      )
    """)
  end

  def down do
    :ok
  end
end

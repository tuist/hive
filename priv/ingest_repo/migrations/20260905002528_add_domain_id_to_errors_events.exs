defmodule Hive.IngestRepo.Migrations.AddDomainIdToErrorsEvents do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE errors_events
      ADD COLUMN IF NOT EXISTS domain_id String AFTER project_id
    """)

    execute("""
    ALTER TABLE errors_events
      ADD INDEX IF NOT EXISTS idx_domain_id domain_id TYPE bloom_filter GRANULARITY 1
    """)
  end

  def down do
    execute("ALTER TABLE errors_events DROP INDEX IF EXISTS idx_domain_id")
    execute("ALTER TABLE errors_events DROP COLUMN IF EXISTS domain_id")
  end
end

defmodule Hive.Repo.Migrations.RenameMeadowsToDomains do
  use Ecto.Migration

  def up do
    rename table(:meadows), to: table(:domains)
    rename table(:meadows_specs), to: table(:domains_specs)
    rename table(:meadow_webhooks), to: table(:domain_webhooks)
    rename table(:forage_github_issue_meadows), to: table(:forage_github_issue_domains)
    rename table(:drop_meadows), to: table(:drop_domains)

    rename table(:domains_specs), :meadow_id, to: :domain_id
    rename table(:domain_webhooks), :meadow_id, to: :domain_id
    rename table(:forage_grafana_alerts), :meadow_id, to: :domain_id
    rename table(:forage_github_issue_domains), :meadow_id, to: :domain_id
    rename table(:drop_domains), :meadow_id, to: :domain_id

    execute "ALTER INDEX meadows_pkey RENAME TO domains_pkey"
    execute "ALTER INDEX meadows_name_index RENAME TO domains_name_index"
    execute "ALTER INDEX meadows_visibility_index RENAME TO domains_visibility_index"
    execute "ALTER INDEX meadows_project_id_index RENAME TO domains_project_id_index"

    execute "ALTER TABLE domains RENAME CONSTRAINT meadows_visibility_check TO domains_visibility_check"
    execute "ALTER TABLE domains RENAME CONSTRAINT meadows_project_id_fkey TO domains_project_id_fkey"

    execute "ALTER INDEX meadows_specs_meadow_id_spec_id_index RENAME TO domains_specs_domain_id_spec_id_index"
    execute "ALTER INDEX meadows_specs_spec_id_index RENAME TO domains_specs_spec_id_index"

    execute "ALTER TABLE domains_specs RENAME CONSTRAINT products_specs_product_id_fkey TO domains_specs_domain_id_fkey"
    execute "ALTER TABLE domains_specs RENAME CONSTRAINT products_specs_spec_id_fkey TO domains_specs_spec_id_fkey"

    execute "ALTER INDEX meadow_webhooks_pkey RENAME TO domain_webhooks_pkey"
    execute "ALTER INDEX meadow_webhooks_token_hash_index RENAME TO domain_webhooks_token_hash_index"
    execute "ALTER INDEX meadow_webhooks_meadow_id_index RENAME TO domain_webhooks_domain_id_index"

    execute "ALTER TABLE domain_webhooks RENAME CONSTRAINT product_webhooks_product_id_fkey TO domain_webhooks_domain_id_fkey"

    execute "ALTER INDEX forage_grafana_alerts_meadow_id_fingerprint_index RENAME TO forage_grafana_alerts_domain_id_fingerprint_index"

    execute "ALTER TABLE forage_grafana_alerts RENAME CONSTRAINT forage_grafana_alerts_product_id_fkey TO forage_grafana_alerts_domain_id_fkey"

    execute "ALTER INDEX forage_github_issue_meadows_pkey RENAME TO forage_github_issue_domains_pkey"
    execute "ALTER INDEX forage_github_issue_meadows_meadow_id_index RENAME TO forage_github_issue_domains_domain_id_index"

    execute "ALTER TABLE forage_github_issue_domains RENAME CONSTRAINT forage_github_issue_meadows_forage_github_issue_id_fkey TO forage_github_issue_domains_forage_github_issue_id_fkey"

    execute "ALTER TABLE forage_github_issue_domains RENAME CONSTRAINT forage_github_issue_meadows_meadow_id_fkey TO forage_github_issue_domains_domain_id_fkey"

    execute "ALTER INDEX drop_meadows_pkey RENAME TO drop_domains_pkey"
    execute "ALTER INDEX drop_meadows_meadow_id_index RENAME TO drop_domains_domain_id_index"

    execute "ALTER TABLE drop_domains RENAME CONSTRAINT drop_meadows_drop_id_fkey TO drop_domains_drop_id_fkey"
    execute "ALTER TABLE drop_domains RENAME CONSTRAINT drop_meadows_meadow_id_fkey TO drop_domains_domain_id_fkey"
  end

  def down do
    execute "ALTER TABLE drop_domains RENAME CONSTRAINT drop_domains_domain_id_fkey TO drop_meadows_meadow_id_fkey"
    execute "ALTER TABLE drop_domains RENAME CONSTRAINT drop_domains_drop_id_fkey TO drop_meadows_drop_id_fkey"

    execute "ALTER INDEX drop_domains_domain_id_index RENAME TO drop_meadows_meadow_id_index"
    execute "ALTER INDEX drop_domains_pkey RENAME TO drop_meadows_pkey"

    execute "ALTER TABLE forage_github_issue_domains RENAME CONSTRAINT forage_github_issue_domains_domain_id_fkey TO forage_github_issue_meadows_meadow_id_fkey"

    execute "ALTER TABLE forage_github_issue_domains RENAME CONSTRAINT forage_github_issue_domains_forage_github_issue_id_fkey TO forage_github_issue_meadows_forage_github_issue_id_fkey"

    execute "ALTER INDEX forage_github_issue_domains_domain_id_index RENAME TO forage_github_issue_meadows_meadow_id_index"
    execute "ALTER INDEX forage_github_issue_domains_pkey RENAME TO forage_github_issue_meadows_pkey"

    execute "ALTER TABLE forage_grafana_alerts RENAME CONSTRAINT forage_grafana_alerts_domain_id_fkey TO forage_grafana_alerts_product_id_fkey"

    execute "ALTER INDEX forage_grafana_alerts_domain_id_fingerprint_index RENAME TO forage_grafana_alerts_meadow_id_fingerprint_index"

    execute "ALTER TABLE domain_webhooks RENAME CONSTRAINT domain_webhooks_domain_id_fkey TO product_webhooks_product_id_fkey"

    execute "ALTER INDEX domain_webhooks_domain_id_index RENAME TO meadow_webhooks_meadow_id_index"
    execute "ALTER INDEX domain_webhooks_token_hash_index RENAME TO meadow_webhooks_token_hash_index"
    execute "ALTER INDEX domain_webhooks_pkey RENAME TO meadow_webhooks_pkey"

    execute "ALTER TABLE domains_specs RENAME CONSTRAINT domains_specs_spec_id_fkey TO products_specs_spec_id_fkey"
    execute "ALTER TABLE domains_specs RENAME CONSTRAINT domains_specs_domain_id_fkey TO products_specs_product_id_fkey"

    execute "ALTER INDEX domains_specs_spec_id_index RENAME TO meadows_specs_spec_id_index"
    execute "ALTER INDEX domains_specs_domain_id_spec_id_index RENAME TO meadows_specs_meadow_id_spec_id_index"

    execute "ALTER TABLE domains RENAME CONSTRAINT domains_project_id_fkey TO meadows_project_id_fkey"
    execute "ALTER TABLE domains RENAME CONSTRAINT domains_visibility_check TO meadows_visibility_check"

    execute "ALTER INDEX domains_project_id_index RENAME TO meadows_project_id_index"
    execute "ALTER INDEX domains_visibility_index RENAME TO meadows_visibility_index"
    execute "ALTER INDEX domains_name_index RENAME TO meadows_name_index"
    execute "ALTER INDEX domains_pkey RENAME TO meadows_pkey"

    rename table(:drop_domains), :domain_id, to: :meadow_id
    rename table(:forage_github_issue_domains), :domain_id, to: :meadow_id
    rename table(:forage_grafana_alerts), :domain_id, to: :meadow_id
    rename table(:domain_webhooks), :domain_id, to: :meadow_id
    rename table(:domains_specs), :domain_id, to: :meadow_id

    rename table(:drop_domains), to: table(:drop_meadows)
    rename table(:forage_github_issue_domains), to: table(:forage_github_issue_meadows)
    rename table(:domain_webhooks), to: table(:meadow_webhooks)
    rename table(:domains_specs), to: table(:meadows_specs)
    rename table(:domains), to: table(:meadows)
  end
end

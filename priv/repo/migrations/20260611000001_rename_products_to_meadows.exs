defmodule Hive.Repo.Migrations.RenameProductsToMeadows do
  use Ecto.Migration

  def up do
    rename table(:products), to: table(:meadows)
    rename table(:products_github_repositories), to: table(:meadows_github_repositories)
    rename table(:products_specs), to: table(:meadows_specs)
    rename table(:product_webhooks), to: table(:meadow_webhooks)

    rename table(:meadows_github_repositories), :product_id, to: :meadow_id
    rename table(:meadows_specs), :product_id, to: :meadow_id
    rename table(:meadow_webhooks), :product_id, to: :meadow_id
    rename table(:forage_grafana_alerts), :product_id, to: :meadow_id

    execute "ALTER INDEX products_pkey RENAME TO meadows_pkey"
    execute "ALTER INDEX products_name_index RENAME TO meadows_name_index"
    execute "ALTER INDEX products_visibility_index RENAME TO meadows_visibility_index"

    execute "ALTER TABLE meadows RENAME CONSTRAINT products_visibility_check TO meadows_visibility_check"

    execute "ALTER INDEX products_github_repositories_unique_index RENAME TO meadows_github_repositories_unique_index"

    execute "ALTER INDEX products_github_repositories_github_repository_id_index RENAME TO meadows_github_repositories_github_repository_id_index"

    execute "ALTER INDEX products_specs_product_id_spec_id_index RENAME TO meadows_specs_meadow_id_spec_id_index"

    execute "ALTER INDEX products_specs_spec_id_index RENAME TO meadows_specs_spec_id_index"

    execute "ALTER INDEX product_webhooks_pkey RENAME TO meadow_webhooks_pkey"
    execute "ALTER INDEX product_webhooks_token_hash_index RENAME TO meadow_webhooks_token_hash_index"
    execute "ALTER INDEX product_webhooks_product_id_index RENAME TO meadow_webhooks_meadow_id_index"

    execute "ALTER INDEX forage_grafana_alerts_product_id_fingerprint_index RENAME TO forage_grafana_alerts_meadow_id_fingerprint_index"
  end

  def down do
    execute "ALTER INDEX forage_grafana_alerts_meadow_id_fingerprint_index RENAME TO forage_grafana_alerts_product_id_fingerprint_index"

    execute "ALTER INDEX meadow_webhooks_meadow_id_index RENAME TO product_webhooks_product_id_index"
    execute "ALTER INDEX meadow_webhooks_token_hash_index RENAME TO product_webhooks_token_hash_index"
    execute "ALTER INDEX meadow_webhooks_pkey RENAME TO product_webhooks_pkey"

    execute "ALTER INDEX meadows_specs_spec_id_index RENAME TO products_specs_spec_id_index"
    execute "ALTER INDEX meadows_specs_meadow_id_spec_id_index RENAME TO products_specs_product_id_spec_id_index"

    execute "ALTER INDEX meadows_github_repositories_github_repository_id_index RENAME TO products_github_repositories_github_repository_id_index"

    execute "ALTER INDEX meadows_github_repositories_unique_index RENAME TO products_github_repositories_unique_index"

    execute "ALTER TABLE meadows RENAME CONSTRAINT meadows_visibility_check TO products_visibility_check"

    execute "ALTER INDEX meadows_visibility_index RENAME TO products_visibility_index"
    execute "ALTER INDEX meadows_name_index RENAME TO products_name_index"
    execute "ALTER INDEX meadows_pkey RENAME TO products_pkey"

    rename table(:forage_grafana_alerts), :meadow_id, to: :product_id
    rename table(:meadow_webhooks), :meadow_id, to: :product_id
    rename table(:meadows_specs), :meadow_id, to: :product_id
    rename table(:meadows_github_repositories), :meadow_id, to: :product_id

    rename table(:meadow_webhooks), to: table(:product_webhooks)
    rename table(:meadows_specs), to: table(:products_specs)
    rename table(:meadows_github_repositories), to: table(:products_github_repositories)
    rename table(:meadows), to: table(:products)
  end
end

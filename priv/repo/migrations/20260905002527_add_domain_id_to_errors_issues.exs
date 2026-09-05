defmodule Hive.Repo.Migrations.AddDomainIdToErrorsIssues do
  @moduledoc """
  Adds `domain_id` to `errors_issues` so events ingested through a
  domain-scoped Data Source Name land in their own issue rows,
  independent of any project-level issue with the same fingerprint.

  The identifying tuple becomes `(project_id, domain_id, fingerprint)`.
  Existing rows keep `domain_id = NULL`, and `NULLS NOT DISTINCT` on the
  new unique index makes NULL count as a single value so the coalescer's
  `ON CONFLICT` still matches one row.
  """

  use Ecto.Migration

  def change do
    alter table(:errors_issues) do
      add :domain_id, references(:domains, type: :binary_id, on_delete: :delete_all)
    end

    drop unique_index(:errors_issues, [:project_id, :fingerprint])

    create unique_index(:errors_issues, [:project_id, :domain_id, :fingerprint],
             nulls_distinct: false,
             name: :errors_issues_project_id_domain_id_fingerprint_index
           )

    create index(:errors_issues, [:domain_id])
  end
end

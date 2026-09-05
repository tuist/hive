defmodule Hive.Repo.Migrations.AddDomainIdToErrorsProjectKeys do
  use Ecto.Migration

  def change do
    alter table(:errors_project_keys) do
      add :domain_id, references(:domains, type: :binary_id, on_delete: :delete_all)
    end

    create index(:errors_project_keys, [:domain_id])

    create unique_index(
             :errors_project_keys,
             [:project_id, :domain_id],
             where: "domain_id IS NOT NULL",
             name: :errors_project_keys_project_id_domain_id_index
           )
  end
end

defmodule Hive.Repo.Migrations.AddItemTypeToForageFeatureRequests do
  use Ecto.Migration

  def change do
    alter table(:forage_feature_requests) do
      add :item_type, :string, null: false, default: "feature_request"
    end

    create constraint(:forage_feature_requests, :forage_feature_requests_item_type_check,
             check: "item_type in ('feature_request', 'bug_report', 'feedback')"
           )

    create index(:forage_feature_requests, [:item_type, :inserted_at])
  end
end

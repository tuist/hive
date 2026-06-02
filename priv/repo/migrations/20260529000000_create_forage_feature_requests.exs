defmodule Hive.Repo.Migrations.CreateForageFeatureRequests do
  use Ecto.Migration

  def change do
    create table(:forage_feature_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text, null: false
      add :requester_email, :string
      add :status, :string, null: false, default: "open"
      add :visibility, :string, null: false, default: "public"

      timestamps(type: :utc_datetime)
    end

    create constraint(:forage_feature_requests, :forage_feature_requests_status_check,
             check: "status in ('open', 'planned', 'closed')"
           )

    create constraint(:forage_feature_requests, :forage_feature_requests_visibility_check,
             check: "visibility in ('public', 'organization')"
           )

    create index(:forage_feature_requests, [:status, :inserted_at])
    create index(:forage_feature_requests, [:visibility])
  end
end

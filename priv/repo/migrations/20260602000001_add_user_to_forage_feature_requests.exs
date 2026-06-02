defmodule Hive.Repo.Migrations.AddUserToForageFeatureRequests do
  use Ecto.Migration

  def change do
    alter table(:forage_feature_requests) do
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:forage_feature_requests, [:user_id])
  end
end

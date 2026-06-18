defmodule Hive.Repo.Migrations.CreateForageItemComments do
  use Ecto.Migration

  def change do
    create table(:forage_item_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false

      add :forage_feature_request_id,
          references(:forage_feature_requests, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:forage_item_comments, [:forage_feature_request_id])
    create index(:forage_item_comments, [:user_id])
  end
end

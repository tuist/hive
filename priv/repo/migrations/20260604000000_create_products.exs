defmodule Hive.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:products, [:name])

    create table(:github_repositories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner, :string, null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:github_repositories, [:owner, :name])

    create table(:products_github_repositories, primary_key: false) do
      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all), null: false

      add :github_repository_id,
          references(:github_repositories, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:products_github_repositories, [:product_id, :github_repository_id],
             name: :products_github_repositories_unique_index
           )

    create index(:products_github_repositories, [:github_repository_id])
  end
end

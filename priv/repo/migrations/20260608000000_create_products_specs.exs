defmodule Hive.Repo.Migrations.CreateProductsSpecs do
  use Ecto.Migration

  def change do
    create table(:products_specs, primary_key: false) do
      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        null: false

      add :spec_id, references(:specs, type: :binary_id, on_delete: :delete_all), null: false
    end

    create unique_index(:products_specs, [:product_id, :spec_id])
    create index(:products_specs, [:spec_id])
  end
end

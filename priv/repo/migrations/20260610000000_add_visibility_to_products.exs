defmodule Hive.Repo.Migrations.AddVisibilityToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :visibility, :string, null: false, default: "public"
    end

    create constraint(:products, :products_visibility_check,
             check: "visibility in ('public', 'private')"
           )

    create index(:products, [:visibility])
  end
end

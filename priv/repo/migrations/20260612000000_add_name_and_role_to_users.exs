defmodule Hive.Repo.Migrations.AddNameAndRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :name, :string
      add :role, :string, null: false, default: "member"
    end

    create index(:users, [:role])
  end
end

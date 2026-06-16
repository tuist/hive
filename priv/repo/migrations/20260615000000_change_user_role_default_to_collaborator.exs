defmodule Hive.Repo.Migrations.ChangeUserRoleDefaultToCollaborator do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE users ALTER COLUMN role SET DEFAULT 'collaborator'")
  end

  def down do
    execute("ALTER TABLE users ALTER COLUMN role SET DEFAULT 'member'")
  end
end

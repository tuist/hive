defmodule Hive.Repo.Migrations.AddApiOauthScope do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO oauth_scopes (id, name, label, public, inserted_at, updated_at)
    VALUES (gen_random_uuid(), 'api', 'Application programming interface', true, now(), now())
    ON CONFLICT (name) DO NOTHING
    """)
  end

  def down do
    execute("DELETE FROM oauth_scopes WHERE name = 'api'")
  end
end

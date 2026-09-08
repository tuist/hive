defmodule Hive.Repo.Migrations.AddGranularMobileOauthScopes do
  use Ecto.Migration

  @scopes [
    {"mobile.me.read", "Mobile: read the signed-in user"},
    {"mobile.forage.read", "Mobile: read forage items"},
    {"mobile.specs.read", "Mobile: read specifications"},
    {"mobile.drops.read", "Mobile: read drops and digests"}
  ]

  def up do
    for {name, label} <- @scopes do
      execute("""
      INSERT INTO oauth_scopes (id, name, label, public, inserted_at, updated_at)
      VALUES (gen_random_uuid(), '#{name}', '#{label}', true, now(), now())
      ON CONFLICT (name) DO NOTHING
      """)
    end
  end

  def down do
    for {name, _label} <- @scopes do
      execute("DELETE FROM oauth_scopes WHERE name = '#{name}'")
    end
  end
end

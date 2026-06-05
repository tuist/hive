ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Hive.Repo, :manual)

# Mimic-copy modules whose helpers we want to stub in tests so async: true
# tests don't have to mutate Application config. Stubs apply per-test
# (process-local), keeping parallelism safe.
Mimic.copy(Hive.Auth)
Mimic.copy(Hive.GitHub.Repositories)
Mimic.copy(Hive.GitHub.Webhooks)

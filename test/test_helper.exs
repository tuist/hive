ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Hive.Repo, :manual)

# Start a single Oban supervisor for the whole test run. Tests configure
# Oban to run in `:manual` testing mode (see config/test.exs) so jobs are
# never picked up by the queues; tests use `Oban.Testing` helpers
# (`all_enqueued/1`, `perform_job/2`) to assert against them. Starting
# Oban once here avoids the named-process collision that happens when
# every test calls `start_supervised!({Oban, ...})` in parallel.
{:ok, _} = Oban.start_link(Application.fetch_env!(:hive, Oban))

# Mimic-copy modules whose helpers we want to stub in tests so async: true
# tests don't have to mutate Application config. Stubs apply per-test
# (process-local), keeping parallelism safe.
Mimic.copy(Hive.Agents)
Mimic.copy(Hive.Specs.Agents.RevisionSummaryAgent)
Mimic.copy(Hive.Auth)
Mimic.copy(Hive.GitHub.Client)
Mimic.copy(Hive.GitHub.Issues)
Mimic.copy(Hive.GitHub.Repositories)
Mimic.copy(Hive.GitHub.Webhooks)
Mimic.copy(Hive.Slack)
Mimic.copy(Hive.Slack.API)
Mimic.copy(Hive.Slack.Installations)
Mimic.copy(Hive.Slack.Signature)
Mimic.copy(HiveWeb.OpenGraph)
Mimic.copy(Boruta.Oauth)
Mimic.copy(Boruta.Openid)
Mimic.copy(Condukt, type_check: true)
Mimic.copy(Condukt.Operation)
Mimic.copy(Req)

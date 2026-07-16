defmodule Hive.Forage.CodingRunsTest do
  use Hive.DataCase, async: true
  use Oban.Testing, repo: Hive.Repo

  alias Condukt.Sandbox
  alias Hive.Accounts
  alias Hive.Forage.CodingRun
  alias Hive.Forage.CodingRunWorker
  alias Hive.Forage.CodingRuns
  alias Hive.Forage.CodingRuns.Workspace
  alias Hive.Forage.Grafana
  alias Hive.Projects
  alias Hive.Projects.Webhooks

  defmodule Source do
    def fetch_source(_repository, opts), do: {:ok, Keyword.fetch!(opts, :source)}

    def publish(repository, source, changes, attrs, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:published, repository, source, changes, attrs})

      {:ok,
       %{
         number: 42,
         title: attrs.title,
         url: "https://github.example/tuist/hive/pull/42"
       }}
    end
  end

  defmodule Sessions do
    def run(agent, prompt, opts) do
      send(Process.get(:coding_runs_test_pid), {:agent_run, agent, prompt, opts})
      :ok = Sandbox.write(opts[:sandbox], "lib/example.ex", "defmodule Example.Fixed do\nend\n")

      {:ok,
       %{
         outcome: "changed",
         summary: "Handled the alert.",
         root_cause: "The example module was incomplete.",
         validation: ["mix test test/example_test.exs"]
       }}
    end
  end

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "coding-runs-#{suffix}@example.com",
        provider: "test",
        provider_uid: "coding-runs-#{suffix}"
      })

    {:ok, user} = Accounts.update_user_role(user, :member)
    {:ok, project} = Projects.create_project(%{name: "Coding runs #{suffix}"})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{owner: "tuist", name: "hive-#{suffix}"})

    {:ok, {webhook, _token}} =
      Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    {:ok, [alert]} = Grafana.ingest(project, webhook, alert_payload("alert-#{suffix}"))
    alert = Repo.preload(alert, :project)

    {:ok, user: user, project: project, repository: repository, alert: alert}
  end

  test "queues a durable run for a linked repository", ctx do
    assert {:ok, run} = create_run(ctx)

    assert run.status == :queued
    assert run.runner == "microsandbox"
    assert run.repository_id == ctx.repository.id
    assert run.requested_by_id == ctx.user.id
    assert run.forage_item_id == "grafana_alert:#{ctx.alert.id}"
    assert run.input["title"] == "High latency"
    assert run.input["project"] == ctx.project.name

    assert_enqueued(
      worker: CodingRunWorker,
      queue: :agents,
      args: %{"coding_run_id" => run.id}
    )
  end

  test "rejects collaborators and repositories from another project", ctx do
    {:ok, collaborator} = Accounts.update_user_role(ctx.user, :collaborator)

    assert {:error, :unauthorized} =
             CodingRuns.create_for_grafana_alert(
               ctx.alert,
               ctx.repository.id,
               collaborator,
               enabled?: fn -> true end
             )

    {:ok, other_project} = Projects.create_project(%{name: "Other project"})

    {:ok, other_repository} =
      Projects.create_repository_for_project(other_project, %{owner: "tuist", name: "other"})

    assert {:error, :repository_not_found} =
             CodingRuns.create_for_grafana_alert(
               ctx.alert,
               other_repository.id,
               %{ctx.user | role: :member},
               enabled?: fn -> true end
             )
  end

  test "allows only one active run for an alert and repository", ctx do
    assert {:ok, first} = create_run(ctx)
    assert {:error, :already_running} = create_run(ctx)

    first
    |> CodingRun.changeset(%{status: :succeeded, result: %{"type" => "report"}})
    |> Repo.update!()

    assert {:ok, second} = create_run(ctx)
    assert second.id != first.id
  end

  test "publishes sandbox changes and does not execute a completed run again", ctx do
    assert {:ok, run} = create_run(ctx)
    source = source_snapshot()
    test_pid = self()
    Process.put(:coding_runs_test_pid, test_pid)

    sandbox_builder = fn opts ->
      {:ok, directory} =
        Workspace.prepare_local(opts[:source_archive], opts[:base_branch])

      send(test_pid, {:workspace, directory})
      Sandbox.new(Condukt.Sandbox.Local, cwd: Path.join(directory, "workspace"))
    end

    assert :ok =
             CodingRuns.execute(run.id,
               source_module: Source,
               sessions_module: Sessions,
               sandbox_builder: sandbox_builder,
               source: source,
               test_pid: test_pid
             )

    assert_receive {:agent_run, Hive.Forage.Agents.GrafanaAlertCodingAgent, prompt, opts}
    assert prompt =~ "High latency"
    assert opts[:max_turns] == 80
    assert opts[:load_project_instructions]

    assert_receive {:published, repository, ^source, changes, attrs}
    assert repository.id == ctx.repository.id
    assert [%{path: "lib/example.ex", deleted?: false, mode: "100644"}] = changes
    assert hd(changes).content == "defmodule Example.Fixed do\nend\n"
    assert attrs.title =~ "fix(forage): address High latency"
    assert attrs.body =~ "## Root cause"
    assert attrs.body =~ "mix test test/example_test.exs"

    completed = CodingRuns.get(run.id)
    assert completed.status == :succeeded
    assert completed.result["type"] == "pull_request"
    assert completed.result["number"] == 42

    assert :ok =
             CodingRuns.execute(run.id,
               source_module: Source,
               source: source,
               test_pid: test_pid
             )

    refute_receive {:published, _, _, _, _}

    assert_receive {:workspace, directory}
    File.rm_rf(directory)
  end

  test "returns runs only to organization members", ctx do
    assert {:ok, run} = create_run(ctx)
    assert CodingRuns.get_for_user(run.id, ctx.user).id == run.id
    assert CodingRuns.get_for_user(run.id, %{ctx.user | role: :collaborator}) == nil
  end

  test "does not spend again when a run has already been claimed", ctx do
    assert {:ok, run} = create_run(ctx)

    run
    |> CodingRun.changeset(%{status: :running, started_at: DateTime.utc_now()})
    |> Repo.update!()

    Process.put(:coding_runs_test_pid, self())
    assert :ok = CodingRuns.execute(run.id, sessions_module: Sessions)
    refute_receive {:agent_run, _, _, _}
  end

  defp create_run(ctx) do
    CodingRuns.create_for_grafana_alert(ctx.alert, ctx.repository.id, ctx.user,
      enabled?: fn -> true end,
      config: [runner: :microsandbox]
    )
  end

  defp alert_payload(fingerprint) do
    %{
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => fingerprint,
          "labels" => %{"alertname" => "HighLatency"},
          "annotations" => %{
            "summary" => "High latency",
            "description" => "Requests exceed the latency budget."
          }
        }
      ]
    }
  end

  defp source_snapshot do
    {:ok, directory} = Briefly.create(directory: true)
    source = Path.join(directory, "source")
    archive = Path.join(directory, "source.tar.gz")
    File.mkdir_p!(Path.join(source, "lib"))
    File.write!(Path.join(source, "lib/example.ex"), "defmodule Example do\nend\n")
    {_, 0} = System.cmd("tar", ["-czf", archive, "-C", directory, "source"])

    %{
      archive: File.read!(archive),
      base_branch: "main",
      base_sha: "base-sha",
      base_tree_sha: "base-tree-sha"
    }
  end
end

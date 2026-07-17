defmodule Hive.Forage.CodingRunsTest do
  use Hive.DataCase, async: true
  use Oban.Testing, repo: Hive.Repo

  alias Condukt.Sandbox
  alias Hive.Accounts
  alias Hive.Flights.Flight
  alias Hive.Forage
  alias Hive.Forage.CodingRunWorker
  alias Hive.Forage.CodingRuns
  alias Hive.Forage.CodingRuns.Workspace
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.Grafana
  alias Hive.Forage.Item
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
    def run_with_session(agent, prompt, opts) do
      send(Process.get(:coding_runs_test_pid), {:agent_run, agent, prompt, opts})
      :ok = Sandbox.write(opts[:sandbox], "lib/example.ex", "defmodule Example.Fixed do\nend\n")

      {:ok,
       %{
         result: %{
           outcome: "changed",
           summary: "Handled the alert.",
           root_cause: "The example module was incomplete.",
           validation: ["mix test test/example_test.exs"]
         },
         session: %{
           "id" => "flight-session",
           "messages" => [%{"role" => "assistant", "content" => "Handled the alert."}]
         }
       }}
    end
  end

  defmodule ReproductionSessions do
    def run_with_session(agent, prompt, opts) do
      send(Process.get(:coding_runs_test_pid), {:agent_run, agent, prompt, opts})

      {:ok,
       %{
         result: %{
           outcome: "not_reproduced",
           summary: "The latency path stayed within budget.",
           root_cause: "The available fixture did not exhibit the production timing.",
           validation: ["mix test test/latency_test.exs"]
         },
         session: %{
           "id" => "reproduction-session",
           "messages" => [%{"role" => "assistant", "content" => "Could not reproduce."}]
         }
       }}
    end
  end

  defmodule IssuePublisher do
    def create_comment(repository, issue_number, body, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:issue_comment, repository, issue_number, body})
      {:ok, %{id: 1}}
    end
  end

  defmodule FailingIssuePublisher do
    def create_comment(_repository, _issue_number, _body, opts) do
      send(Keyword.fetch!(opts, :test_pid), :issue_comment_attempted)
      {:error, :rate_limited}
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
    |> Flight.changeset(%{status: :succeeded, result: %{"type" => "report"}})
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
    assert opts[:inference_role] == :coding
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
    assert completed.result["base_revision"] == "base-sha"
    assert completed.session["id"] == "flight-session"
    assert completed.session["source"]["repository"] == completed.repository_full_name
    assert completed.session["source"]["base_revision"] == "base-sha"

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

  test "treats a not-reproduced objective outcome as a successful Flight", ctx do
    {:ok, item} = Forage.get_item_for_user("grafana_alert:#{ctx.alert.id}", ctx.user)

    assert {:ok, run} =
             CodingRuns.create_for_item(item, ctx.repository.id, ctx.user,
               objective: :reproduce,
               enabled?: fn -> true end,
               config: [runner: :microsandbox]
             )

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
               sessions_module: ReproductionSessions,
               sandbox_builder: sandbox_builder,
               source: source,
               test_pid: test_pid
             )

    assert_receive {:agent_run, Hive.Forage.Agents.ReproductionAgent, prompt, _opts}
    assert prompt =~ "Try to reproduce this Forage item"
    refute_receive {:published, _, _, _, _}

    completed = CodingRuns.get(run.id)
    assert completed.status == :succeeded
    assert completed.objective == :reproduce
    assert completed.objective_outcome == :not_reproduced
    assert completed.result["type"] == "report"
    assert completed.result["objective_outcome"] == "not_reproduced"
    assert completed.result["base_revision"] == "base-sha"

    assert_receive {:workspace, directory}
    File.rm_rf(directory)
  end

  test "publishes a reproduction report back to a GitHub issue", ctx do
    issue_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    item = %Item{
      id: "github_issue:#{issue_id}",
      type: :github_issue,
      origin: :github,
      source_record_id: issue_id,
      source_record: %GitHubIssue{id: issue_id, number: 42},
      title: "Intermittent latency",
      body: "The request occasionally exceeds its budget.",
      status: :open,
      source_label: "tuist/#{ctx.repository.name}",
      repository_id: ctx.repository.id,
      updated_at: now
    }

    assert {:ok, run} =
             CodingRuns.create_for_item(item, ctx.repository.id, ctx.user,
               objective: :reproduce,
               enabled?: fn -> true end,
               config: [runner: :microsandbox]
             )

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
               sessions_module: ReproductionSessions,
               issues_module: IssuePublisher,
               sandbox_builder: sandbox_builder,
               source: source,
               test_pid: test_pid
             )

    assert_receive {:issue_comment, repository, 42, body}
    assert repository.id == ctx.repository.id
    assert body =~ "**Reproduce** Flight"
    assert body =~ "**Not reproduced**"
    assert body =~ "/flights/#{run.id}"

    assert CodingRuns.get(run.id).status == :succeeded

    assert_receive {:workspace, directory}
    File.rm_rf(directory)
  end

  test "persists a completed report even when publishing it to GitHub fails", ctx do
    issue_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    item = %Item{
      id: "github_issue:#{issue_id}",
      type: :github_issue,
      origin: :github,
      source_record_id: issue_id,
      source_record: %GitHubIssue{id: issue_id, number: 42},
      title: "Intermittent latency",
      body: "The request occasionally exceeds its budget.",
      status: :open,
      source_label: "tuist/#{ctx.repository.name}",
      repository_id: ctx.repository.id,
      updated_at: now
    }

    assert {:ok, run} =
             CodingRuns.create_for_item(item, ctx.repository.id, ctx.user,
               objective: :reproduce,
               enabled?: fn -> true end,
               config: [runner: :microsandbox]
             )

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
               sessions_module: ReproductionSessions,
               issues_module: FailingIssuePublisher,
               sandbox_builder: sandbox_builder,
               source: source,
               test_pid: test_pid
             )

    assert_receive :issue_comment_attempted

    completed = CodingRuns.get(run.id)
    assert completed.status == :succeeded
    assert completed.objective_outcome == :not_reproduced
    assert completed.result["type"] == "report"
    assert completed.result["summary"] == "The latency path stayed within budget."

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
    |> Flight.changeset(%{status: :running, started_at: DateTime.utc_now()})
    |> Repo.update!()

    Process.put(:coding_runs_test_pid, self())
    assert :ok = CodingRuns.execute(run.id, sessions_module: Sessions)
    refute_receive {:agent_run, _, _, _}
  end

  test "records a terminal failure after the linked repository is removed", ctx do
    assert {:ok, run} = create_run(ctx)

    assert {:ok, _repository} =
             Projects.delete_repository_from_project(ctx.project, ctx.repository.id)

    assert :ok = CodingRuns.execute(run.id)

    failed = CodingRuns.get(run.id)
    assert failed.status == :failed
    assert failed.repository_id == nil
    assert failed.completed_at
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

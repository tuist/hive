defmodule HiveWeb.ForageLive.ShowTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Forage.CodingRun
  alias Hive.Forage.CodingRuns
  alias Hive.Forage.Grafana
  alias Hive.Projects
  alias Hive.Projects.Webhooks
  alias Hive.Repo

  test "lets a member manually queue a coding run for a Grafana alert", %{conn: conn} do
    {conn, user} = sign_in(conn, "coding-run-live@example.com")
    {:ok, project} = Projects.create_project(%{name: "Coding run project"})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{owner: "tuist", name: unique_repo()})

    {:ok, {webhook, _token}} =
      Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    {:ok, [alert]} = Grafana.ingest(project, webhook, alert_payload())
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    run = %CodingRun{
      id: Ecto.UUID.generate(),
      forage_item_id: "grafana_alert:#{alert.id}",
      status: :queued,
      runner: "microsandbox",
      repository_full_name: "tuist/#{repository.name}",
      repository_id: repository.id,
      requested_by_id: user.id,
      input: %{},
      inserted_at: now,
      updated_at: now
    }

    stub(CodingRuns, :enabled?, fn -> true end)

    expect(CodingRuns, :create_for_grafana_alert, fn fetched_alert, repository_id, caller ->
      assert fetched_alert.id == alert.id
      assert repository_id == repository.id
      assert caller.id == user.id
      {:ok, run}
    end)

    {:ok, view, html} = live(conn, ~p"/forage/items/grafana-alert/#{alert.id}")

    assert html =~ "Coding runs"
    assert html =~ "tuist/#{repository.name}"
    assert html =~ "Start run"

    html =
      view
      |> form("#forage-coding-run-form", coding_run: %{repository_id: repository.id})
      |> render_submit()

    assert html =~ "Coding run queued. The result will appear here."
  end

  test "explains when the coding runner is not configured", %{conn: conn} do
    {conn, _user} = sign_in(conn, "coding-run-disabled@example.com")
    {:ok, project} = Projects.create_project(%{name: "Disabled coding run"})

    {:ok, _repository} =
      Projects.create_repository_for_project(project, %{owner: "tuist", name: unique_repo()})

    {:ok, {webhook, _token}} =
      Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    {:ok, [alert]} = Grafana.ingest(project, webhook, alert_payload())
    stub(CodingRuns, :enabled?, fn -> false end)

    {:ok, _view, html} = live(conn, ~p"/forage/items/grafana-alert/#{alert.id}")

    assert html =~ "New runs are paused"
    refute html =~ ">Start run<"
  end

  test "presents pull requests, reports, and failures as distinct run outcomes", %{conn: conn} do
    {conn, user} = sign_in(conn, "coding-run-history@example.com")
    {:ok, project} = Projects.create_project(%{name: "Coding run history"})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{owner: "tuist", name: unique_repo()})

    {:ok, {webhook, _token}} =
      Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    {:ok, [alert]} = Grafana.ingest(project, webhook, alert_payload())
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    pull_request =
      insert_coding_run(alert, repository, user, %{
        status: :succeeded,
        started_at: DateTime.add(now, -960, :second),
        completed_at: now,
        result: %{
          "type" => "pull_request",
          "title" => "fix(web): bound alert latency queries",
          "summary" => "Bounded the slow request path.",
          "url" => "https://example.invalid/pull/42",
          "validation" => ["mix test", "mix compile"]
        }
      })

    insert_coding_run(alert, repository, user, %{
      status: :succeeded,
      started_at: DateTime.add(now, -420, :second),
      completed_at: now,
      result: %{
        "type" => "report",
        "outcome" => "no_change",
        "summary" => "No safe code change was available.",
        "root_cause" => "The alert recovered before the failure could be reproduced."
      }
    })

    insert_coding_run(alert, repository, user, %{
      status: :failed,
      started_at: DateTime.add(now, -60, :second),
      completed_at: now,
      error: "The sandbox stopped before the coding harness could start."
    })

    stub(CodingRuns, :enabled?, fn -> false end)

    {:ok, view, html} = live(conn, ~p"/forage/items/grafana-alert/#{alert.id}")

    assert html =~ "Latest activity"
    assert html =~ "3 runs"
    assert html =~ "fix(web): bound alert latency queries"
    assert html =~ "Pull request"
    assert html =~ "2 checks"
    assert html =~ "No code change needed"
    assert html =~ "Finding"
    assert html =~ "The alert recovered before the failure could be reproduced."
    assert html =~ "The sandbox stopped before the coding harness could start."
    assert html =~ "Microsandbox"

    assert has_element?(
             view,
             "#coding-run-#{pull_request.id} [data-part=coding-run-status][data-status=success]"
           )
  end

  defp unique_repo, do: "hive-#{System.unique_integer([:positive])}"

  defp insert_coding_run(alert, repository, user, attrs) do
    defaults = %{
      forage_item_id: "grafana_alert:#{alert.id}",
      runner: "microsandbox",
      repository_full_name: "tuist/#{repository.name}",
      repository_id: repository.id,
      requested_by_id: user.id,
      input: %{"kind" => "grafana_alert"}
    }

    %CodingRun{}
    |> CodingRun.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp alert_payload do
    %{
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => "live-#{System.unique_integer([:positive])}",
          "labels" => %{"alertname" => "HighLatency"},
          "annotations" => %{
            "summary" => "High latency",
            "description" => "Requests exceed the latency budget."
          }
        }
      ]
    }
  end
end

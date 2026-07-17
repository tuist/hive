defmodule HiveWeb.ForageLive.ShowTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Flights
  alias Hive.Flights.Flight
  alias Hive.Domains
  alias Hive.Forage.CodingRuns
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.Grafana
  alias Hive.GitHub.Issues
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

    run = %Flight{
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

    expect(Flights, :start_for_item, fn item, repository_id, caller, opts ->
      assert item.source_record.id == alert.id
      assert repository_id == repository.id
      assert caller.id == user.id
      assert opts[:objective] == "reproduce"
      assert opts[:trigger] == %{"source" => "dashboard"}
      {:ok, run}
    end)

    {:ok, view, html} = live(conn, ~p"/forage/items/grafana-alert/#{alert.id}")

    assert html =~ "Flights"
    assert html =~ "tuist/#{repository.name}"
    assert html =~ "Start Flight"

    html =
      view
      |> form("#forage-coding-run-form",
        coding_run: %{repository_id: repository.id, objective: "reproduce"}
      )
      |> render_submit()

    assert html =~ "Flight queued. The result will appear here."
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

    assert html =~ "New Flights are paused"
    refute html =~ ">Start Flight<"
  end

  test "starts an objective-specific Flight from a GitHub issue detail page", %{conn: conn} do
    {conn, user} = sign_in(conn, "github-issue-flight@example.com")
    suffix = System.unique_integer([:positive])
    {:ok, project} = Projects.create_project(%{name: "Issue Flight #{suffix}"})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Issue Flight #{suffix}",
        project_id: project.id,
        github_repository_owner: "tuist",
        github_repository_name: "issue-flight-#{suffix}"
      })

    repository = github_repository_for_domain!(domain)

    issue =
      %GitHubIssue{}
      |> GitHubIssue.changeset(%{
        github_repository_id: repository.id,
        number: 42,
        title: "Intermittent latency",
        body: "The request occasionally exceeds its budget.",
        state: :open
      })
      |> Repo.insert!()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    flight = %Flight{
      id: Ecto.UUID.generate(),
      forage_item_id: "github_issue:#{issue.id}",
      status: :queued,
      objective: :investigate,
      runner: "microsandbox",
      repository_full_name: "tuist/#{repository.name}",
      repository_id: repository.id,
      requested_by_id: user.id,
      input: %{},
      inserted_at: now,
      updated_at: now
    }

    stub(Issues, :list_comments, fn fetched_repository, 42, _opts ->
      assert fetched_repository.id == repository.id
      {:ok, []}
    end)

    stub(CodingRuns, :enabled?, fn -> true end)

    expect(Flights, :start_for_item, fn item, repository_id, caller, opts ->
      assert item.id == "github_issue:#{issue.id}"
      assert repository_id == repository.id
      assert caller.id == user.id
      assert opts[:objective] == "investigate"
      {:ok, flight}
    end)

    {:ok, view, html} = live(conn, ~p"/forage/items/github-issue/#{issue.id}")

    assert html =~ "Flights"
    assert html =~ "Investigate"
    assert html =~ "Start Flight"
    assert has_element?(view, "#forage-coding-run-objective")

    html =
      view
      |> form("#forage-coding-run-form",
        coding_run: %{repository_id: repository.id, objective: "investigate"}
      )
      |> render_submit()

    assert html =~ "Flight queued. The result will appear here."
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
    assert html =~ "3 Flights"
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

    %Flight{}
    |> Flight.changeset(Map.merge(defaults, attrs))
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

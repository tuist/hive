defmodule HiveWeb.FlightLive.ShowTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Flights.Flight
  alias Hive.Forage.Grafana
  alias Hive.Projects
  alias Hive.Projects.Webhooks
  alias Hive.Repo

  test "shows the outcome, Forage relation, and portable session", %{conn: conn} do
    {conn, user} = sign_in(conn, "flight-show@example.com")
    {:ok, project} = Projects.create_project(%{name: "Flight show"})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{owner: "tuist", name: unique_repo()})

    {:ok, {webhook, _token}} =
      Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    {:ok, [alert]} = Grafana.ingest(project, webhook, alert_payload())
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    flight =
      %Flight{}
      |> Flight.changeset(%{
        forage_item_id: "grafana_alert:#{alert.id}",
        status: :succeeded,
        objective: :fix,
        objective_outcome: :fixed,
        trigger: %{"source" => "slack"},
        runner: "kubernetes",
        runner_id: "sandbox-123",
        repository_full_name: "tuist/#{repository.name}",
        repository_id: repository.id,
        requested_by_id: user.id,
        input: %{"title" => "High latency"},
        session: %{
          "source" => %{"base_branch" => "main", "base_revision" => "abc123"},
          "messages" => [
            %{"role" => "user", "content" => "Investigate the alert."},
            %{
              "role" => "assistant",
              "content" => [
                %{
                  "type" => "tool_call",
                  "name" => "read",
                  "arguments" => %{"path" => "lib/hive.ex"}
                },
                %{"type" => "text", "text" => "The query was unbounded."}
              ]
            }
          ]
        },
        result: %{
          "type" => "pull_request",
          "summary" => "Bounded the query.",
          "root_cause" => "The query had no limit.",
          "validation" => ["mix test"],
          "branch" => "hive/flight-123",
          "url" => "https://example.invalid/pull/42"
        },
        started_at: DateTime.add(now, -120, :second),
        completed_at: now
      })
      |> Repo.insert!()

    {:ok, view, html} = live(conn, ~p"/flights/#{flight.id}")

    assert html =~ "High latency"
    assert html =~ "Bounded the query."
    assert html =~ "The query had no limit."
    assert html =~ "Investigate the alert."
    assert html =~ "The query was unbounded."
    assert html =~ "Objective"
    assert html =~ "Fixed"
    assert html =~ "Slack"
    assert html =~ "git checkout hive/flight-123"
    assert html =~ ~s(get_flight {&quot;id&quot;:&quot;#{flight.id}&quot;})
    assert has_element?(view, "a[href='/forage/items/grafana-alert/#{alert.id}']")
  end

  test "hides a Flight from collaborators", %{conn: conn} do
    {conn, user} = sign_in(conn, "flight-show-collaborator@example.com")
    {:ok, _user} = Hive.Accounts.update_user_role(user, :collaborator)

    assert {:error, {:live_redirect, %{to: "/flights"}}} =
             live(conn, ~p"/flights/#{Ecto.UUID.generate()}")
  end

  defp unique_repo, do: "hive-#{System.unique_integer([:positive])}"

  defp alert_payload do
    %{
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => "flight-show-#{System.unique_integer([:positive])}",
          "labels" => %{"alertname" => "HighLatency"},
          "annotations" => %{"summary" => "High latency"}
        }
      ]
    }
  end
end

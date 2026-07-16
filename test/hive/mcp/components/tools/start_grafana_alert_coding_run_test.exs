defmodule Hive.MCP.Components.Tools.StartGrafanaAlertCodingRunTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.Forage.CodingRun
  alias Hive.Forage.CodingRuns
  alias Hive.Forage.Grafana
  alias Hive.MCP.Components.Tools.StartGrafanaAlertCodingRun
  alias Hive.Projects
  alias Hive.Projects.Webhooks

  test "starts a coding run for an organization member" do
    user = mcp_user("coding-run-member@example.com", :member)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

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
      runner: "kubernetes",
      repository_full_name: "tuist/#{repository.name}",
      repository_id: repository.id,
      requested_by_id: user.id,
      input: %{},
      inserted_at: now,
      updated_at: now
    }

    expect(CodingRuns, :create_for_grafana_alert, fn fetched_alert, repository_id, caller ->
      assert fetched_alert.id == alert.id
      assert repository_id == repository.id
      assert caller.id == user.id
      {:ok, run}
    end)

    response =
      user
      |> mcp_conn()
      |> StartGrafanaAlertCodingRun.call(%{
        "alert_id" => "grafana_alert:#{alert.id}",
        "repository_id" => repository.id
      })
      |> response_json()

    assert response["coding_run"]["id"] == run.id
    assert response["coding_run"]["status"] == "queued"
    assert response["coding_run"]["runner"] == "kubernetes"
  end

  test "rejects collaborators" do
    user = mcp_user("coding-run-collaborator@example.com", :collaborator)

    response =
      user
      |> mcp_conn()
      |> StartGrafanaAlertCodingRun.call(%{
        "alert_id" => Ecto.UUID.generate(),
        "repository_id" => Ecto.UUID.generate()
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end

  defp unique_repo, do: "hive-#{System.unique_integer([:positive])}"

  defp alert_payload do
    %{
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => "mcp-#{System.unique_integer([:positive])}",
          "labels" => %{"alertname" => "HighLatency"},
          "annotations" => %{"summary" => "High latency"}
        }
      ]
    }
  end
end

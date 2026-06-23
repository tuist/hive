defmodule HiveWeb.ForageLive.GrafanaAlertsTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Auth
  alias Hive.Forage.Grafana
  alias Hive.Projects
  alias Hive.Projects.Webhooks

  defp create_project!(attrs) do
    attrs =
      Map.merge(
        %{name: "Project #{System.unique_integer([:positive])}"},
        attrs
      )

    {:ok, project} = Projects.create_project(attrs)
    project
  end

  test "hides organization-only alerts from guests", %{conn: conn} do
    Mimic.stub(Auth, :member?, fn _ -> false end)
    project = create_project!(%{name: "Guest hidden"})

    {:ok, {webhook, _}} =
      Webhooks.create(project, %{"name" => "G", "source" => "grafana"})

    {:ok, [_]} =
      Grafana.ingest(project, webhook, %{
        "alerts" => [
          %{
            "status" => "firing",
            "fingerprint" => "guest-hidden",
            "labels" => %{"alertname" => "GuestHiddenLatency"},
            "annotations" => %{"summary" => "Guest hidden latency"}
          }
        ]
      })

    {:ok, _view, html} = live(conn, ~p"/forage")

    refute html =~ "Guest hidden latency"
  end

  test "renders the empty state for organization members", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, _view, html} =
      live(conn, ~p"/forage?filter_type_op===&filter_type_val=grafana_alert")

    assert html =~ "Forage"
    assert html =~ "No forage items found"
  end

  test "lists ingested alerts with project and status", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    project = create_project!(%{name: "Hive"})

    {:ok, {webhook, _}} =
      Webhooks.create(project, %{"name" => "G", "source" => "grafana"})

    {:ok, [_]} =
      Grafana.ingest(project, webhook, %{
        "status" => "firing",
        "alerts" => [
          %{
            "status" => "firing",
            "fingerprint" => "fp-1",
            "labels" => %{"alertname" => "HighLatency"},
            "annotations" => %{
              "summary" => "Latency over budget",
              "description" => "p95 > 500ms"
            },
            "startsAt" => "2026-06-10T12:00:00Z",
            "generatorURL" => "https://grafana.example/alert"
          }
        ]
      })

    {:ok, _view, html} =
      live(conn, ~p"/forage?filter_type_op===&filter_type_val=grafana_alert")

    assert html =~ "Latency over budget"
    assert html =~ "p95 &gt; 500ms"
    assert html =~ "Firing"
    assert html =~ "Hive"
    assert html =~ "Open in Grafana"
  end
end

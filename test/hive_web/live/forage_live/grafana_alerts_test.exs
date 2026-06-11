defmodule HiveWeb.ForageLive.GrafanaAlertsTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Auth
  alias Hive.Forage.Grafana
  alias Hive.Meadows
  alias Hive.Meadows.Webhooks

  test "redirects guests away from the organization-only source", %{conn: conn} do
    Mimic.stub(Auth, :member?, fn _ -> false end)

    assert {:error, {:redirect, %{to: "/forage/feature-requests"}}} =
             live(conn, ~p"/forage/grafana-alerts")
  end

  test "renders the empty state for organization members", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, _view, html} = live(conn, ~p"/forage/grafana-alerts")

    assert html =~ "Grafana alerts"
    assert html =~ "No Grafana alerts yet"
  end

  test "lists ingested alerts with meadow and status", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    {:ok, meadow} = Meadows.create_meadow(%{name: "Hive"})

    {:ok, {webhook, _}} =
      Webhooks.create(meadow, %{"name" => "G", "source" => "grafana"})

    {:ok, [_]} =
      Grafana.ingest(meadow, webhook, %{
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

    {:ok, _view, html} = live(conn, ~p"/forage/grafana-alerts")

    assert html =~ "Latency over budget"
    assert html =~ "p95 &gt; 500ms"
    assert html =~ "Firing"
    assert html =~ "Hive"
    assert html =~ "Open in Grafana"
  end
end

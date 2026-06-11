defmodule Hive.Forage.GrafanaTest do
  use Hive.DataCase, async: true

  alias Hive.Forage
  alias Hive.Forage.Grafana
  alias Hive.Forage.GrafanaAlert
  alias Hive.Meadows
  alias Hive.Meadows.Webhooks

  setup do
    {:ok, meadow} = Meadows.create_meadow(%{name: "Hive"})

    {:ok, {webhook, _token}} =
      Webhooks.create(meadow, %{"name" => "G", "source" => "grafana"})

    {:ok, meadow: meadow, webhook: webhook}
  end

  test "ingest/3 inserts an alert from a firing payload", ctx do
    payload = %{
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
          "endsAt" => "0001-01-01T00:00:00Z",
          "generatorURL" => "https://grafana.example/alert"
        }
      ]
    }

    assert {:ok, [%GrafanaAlert{} = alert]} = Grafana.ingest(ctx.meadow, ctx.webhook, payload)
    assert alert.status == :firing
    assert alert.title == "Latency over budget"
    assert alert.summary == "p95 > 500ms"
    assert alert.fingerprint == "fp-1"
    assert alert.generator_url == "https://grafana.example/alert"
    assert alert.labels == %{"alertname" => "HighLatency"}
    assert alert.starts_at == ~U[2026-06-10 12:00:00Z]
    assert alert.ends_at == nil
    assert alert.meadow_id == ctx.meadow.id
    assert alert.webhook_id == ctx.webhook.id
  end

  test "ingest/3 threads firing + resolved into one row, updating status", ctx do
    firing = base_payload("firing", "fp-1")
    resolved = base_payload("resolved", "fp-1")

    assert {:ok, [first]} = Grafana.ingest(ctx.meadow, ctx.webhook, firing)
    assert first.status == :firing

    assert {:ok, [second]} = Grafana.ingest(ctx.meadow, ctx.webhook, resolved)
    assert second.id == first.id
    assert second.status == :resolved
    assert [%GrafanaAlert{}] = Forage.list_grafana_alerts()
  end

  test "ingest/3 rejects a payload without alerts", ctx do
    assert {:error, :invalid_payload} =
             Grafana.ingest(ctx.meadow, ctx.webhook, %{"foo" => "bar"})
  end

  test "ingest/3 derives a fingerprint when Grafana doesn't send one", ctx do
    payload = %{
      "status" => "firing",
      "alerts" => [
        %{
          "status" => "firing",
          "labels" => %{"alertname" => "Nameless"},
          "annotations" => %{}
        }
      ]
    }

    assert {:ok, [alert]} = Grafana.ingest(ctx.meadow, ctx.webhook, payload)
    assert is_binary(alert.fingerprint) and byte_size(alert.fingerprint) > 0
  end

  defp base_payload(status, fingerprint) do
    %{
      "status" => status,
      "alerts" => [
        %{
          "status" => status,
          "fingerprint" => fingerprint,
          "labels" => %{"alertname" => "HighLatency"},
          "annotations" => %{"summary" => "Latency", "description" => "details"},
          "startsAt" => "2026-06-10T12:00:00Z"
        }
      ]
    }
  end
end

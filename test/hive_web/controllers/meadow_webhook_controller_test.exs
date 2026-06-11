defmodule HiveWeb.MeadowWebhookControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Forage
  alias Hive.Meadows
  alias Hive.Meadows.Webhooks

  setup do
    {:ok, meadow} = Meadows.create_meadow(%{name: "Hive"})

    {:ok, {webhook, token}} =
      Webhooks.create(meadow, %{"name" => "G", "source" => "grafana"})

    {:ok, meadow: meadow, webhook: webhook, token: token}
  end

  test "POST accepts a valid Grafana payload and upserts alerts", ctx do
    body = %{
      "status" => "firing",
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => "fp-1",
          "labels" => %{"alertname" => "X"},
          "annotations" => %{"summary" => "Boom"},
          "startsAt" => "2026-06-10T12:00:00Z"
        }
      ]
    }

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/meadows/#{ctx.meadow.id}/grafana/#{ctx.token}", body)

    assert response(conn, 202) == ""
    assert [_alert] = Forage.list_grafana_alerts()
  end

  test "POST rejects an unknown token", ctx do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/meadows/#{ctx.meadow.id}/grafana/hwh_nope", %{
        "status" => "firing",
        "alerts" => [%{"fingerprint" => "x"}]
      })

    assert response(conn, 401) == ""
  end

  test "POST 404s on an unknown meadow", ctx do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/webhooks/meadows/00000000-0000-0000-0000-000000000000/grafana/#{ctx.token}",
        %{"status" => "firing", "alerts" => [%{"fingerprint" => "x"}]}
      )

    assert response(conn, 404) == ""
  end

  test "POST 422s on a payload without alerts", ctx do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/meadows/#{ctx.meadow.id}/grafana/#{ctx.token}", %{
        "status" => "firing"
      })

    assert response(conn, 422) == ""
  end

  test "POST rejects an unknown source", ctx do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/meadows/#{ctx.meadow.id}/pagerduty/#{ctx.token}", %{
        "alerts" => []
      })

    assert response(conn, 401) == ""
  end
end

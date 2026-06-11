defmodule HiveWeb.ProductWebhookControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Forage
  alias Hive.Products
  alias Hive.Products.Webhooks

  setup do
    {:ok, product} = Products.create_product(%{name: "Hive"})

    {:ok, {webhook, token}} =
      Webhooks.create(product, %{"name" => "G", "source" => "grafana"})

    {:ok, product: product, webhook: webhook, token: token}
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
      |> post(~p"/webhooks/products/#{ctx.product.id}/grafana/#{ctx.token}", body)

    assert response(conn, 202) == ""
    assert [_alert] = Forage.list_grafana_alerts()
  end

  test "POST rejects an unknown token", ctx do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/products/#{ctx.product.id}/grafana/hwh_nope", %{
        "status" => "firing",
        "alerts" => [%{"fingerprint" => "x"}]
      })

    assert response(conn, 401) == ""
  end

  test "POST 404s on an unknown product", ctx do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/webhooks/products/00000000-0000-0000-0000-000000000000/grafana/#{ctx.token}",
        %{"status" => "firing", "alerts" => [%{"fingerprint" => "x"}]}
      )

    assert response(conn, 404) == ""
  end

  test "POST 422s on a payload without alerts", ctx do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/products/#{ctx.product.id}/grafana/#{ctx.token}", %{
        "status" => "firing"
      })

    assert response(conn, 422) == ""
  end

  test "POST rejects an unknown source", ctx do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/products/#{ctx.product.id}/pagerduty/#{ctx.token}", %{
        "alerts" => []
      })

    assert response(conn, 401) == ""
  end
end

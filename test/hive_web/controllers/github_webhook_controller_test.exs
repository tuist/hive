defmodule HiveWeb.GitHubWebhookControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.GitHub.Webhooks

  @secret "webhook-secret"
  @body ~s({"zen":"Keep it logically awesome."})

  test "POST /webhooks/github accepts a signed GitHub webhook", %{conn: conn} do
    stub(Webhooks, :secret, fn -> {:ok, @secret} end)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-github-event", "ping")
      |> put_req_header("x-hub-signature-256", signature(@body, @secret))
      |> post(~p"/webhooks/github", @body)

    assert response(conn, 202) == ""
  end

  test "POST /webhooks/github dispatches the authenticated event", %{conn: conn} do
    stub(Webhooks, :secret, fn -> {:ok, @secret} end)
    body = ~s({"action":"closed","pull_request":{"merged":true}})

    expect(Webhooks, :handle_event, fn "pull_request",
                                       %{
                                         "action" => "closed",
                                         "pull_request" => %{"merged" => true}
                                       } ->
      :ok
    end)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-github-event", "pull_request")
      |> put_req_header("x-hub-signature-256", signature(body, @secret))
      |> post(~p"/webhooks/github", body)

    assert response(conn, 202) == ""
  end

  test "POST /webhooks/github rejects an invalid signature", %{conn: conn} do
    stub(Webhooks, :secret, fn -> {:ok, @secret} end)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-github-event", "ping")
      |> put_req_header("x-hub-signature-256", signature(@body, "other-secret"))
      |> post(~p"/webhooks/github", @body)

    assert response(conn, 401) == ""
  end

  test "POST /webhooks/github rejects requests without a signature", %{conn: conn} do
    stub(Webhooks, :secret, fn -> {:ok, @secret} end)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-github-event", "ping")
      |> post(~p"/webhooks/github", @body)

    assert response(conn, 401) == ""
  end

  test "POST /webhooks/github returns unavailable when the secret is missing", %{conn: conn} do
    stub(Webhooks, :secret, fn -> {:error, :not_configured} end)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-github-event", "ping")
      |> put_req_header("x-hub-signature-256", signature(@body, @secret))
      |> post(~p"/webhooks/github", @body)

    assert response(conn, 503) == ""
  end

  defp signature(body, secret) do
    digest =
      :hmac
      |> :crypto.mac(:sha256, secret, body)
      |> Base.encode16(case: :lower)

    "sha256=#{digest}"
  end
end

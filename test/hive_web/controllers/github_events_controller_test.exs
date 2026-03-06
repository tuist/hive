defmodule HiveWeb.GitHubEventsControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Integrations

  defp create_app do
    {:ok, app} =
      Integrations.create_github_app(%{
        name: "Test App",
        webhook_secret: "test_webhook_secret",
        app_id: "123",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        installation_id: "456"
      })

    {:ok, _} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "hive"})
    app
  end

  defp sign_payload(body, secret) do
    "sha256=" <>
      (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))
  end

  defp post_signed(conn, app, event_type, payload) do
    body = Jason.encode!(payload)
    signature = sign_payload(body, app.webhook_secret)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", event_type)
    |> put_req_header("x-hub-signature-256", signature)
    |> post(~p"/api/github/events", body)
  end

  describe "POST /api/github/events" do
    test "returns 200 with valid signature for an issue event", %{conn: conn} do
      app = create_app()

      payload = %{
        "action" => "opened",
        "repository" => %{"full_name" => "tuist/hive"},
        "issue" => %{
          "title" => "Test issue",
          "body" => "Test body",
          "number" => 1,
          "html_url" => "https://github.com/tuist/hive/issues/1",
          "created_at" => "2026-03-06T12:00:00Z",
          "user" => %{"login" => "testuser"}
        }
      }

      conn = post_signed(conn, app, "issues", payload)
      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "returns 401 with invalid signature", %{conn: conn} do
      _app = create_app()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "issues")
        |> put_req_header("x-hub-signature-256", "sha256=invalid")
        |> post(~p"/api/github/events", Jason.encode!(%{"action" => "opened"}))

      assert json_response(conn, 401) == %{"error" => "invalid signature"}
    end

    test "returns 401 when no app is configured", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "issues")
        |> put_req_header("x-hub-signature-256", "sha256=something")
        |> post(~p"/api/github/events", Jason.encode!(%{"action" => "opened"}))

      assert json_response(conn, 401) == %{"error" => "not configured"}
    end
  end
end

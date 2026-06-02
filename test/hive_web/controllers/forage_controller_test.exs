defmodule HiveWeb.ForageControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts

  test "GET /forage/feature-requests renders public feature requests", %{conn: conn} do
    conn = get(conn, ~p"/forage/feature-requests")

    assert html_response(conn, 200) =~ "Feature requests"
  end

  test "GET /forage/feature-requests/new redirects guests to login", %{conn: conn} do
    conn = get(conn, ~p"/forage/feature-requests/new")

    assert redirected_to(conn) == ~p"/login"
  end

  test "POST /forage/feature-requests creates a request for the signed-in user", %{conn: conn} do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "alice@example.com",
        provider: "test",
        provider_uid: "alice"
      })

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> post(~p"/forage/feature-requests", %{
        "feature_request" => %{
          "title" => "GitHub sign-in",
          "description" => "Let requesters sign in with GitHub."
        }
      })

    assert redirected_to(conn) == ~p"/forage/feature-requests"

    conn = get(build_conn(), ~p"/forage/feature-requests")
    response = html_response(conn, 200)

    assert response =~ "GitHub sign-in"
    assert response =~ "Submitted by alice@example.com"
  end

  test "GET /forage/grafana-alerts is hidden from guests", %{conn: conn} do
    conn = get(conn, ~p"/forage/grafana-alerts")

    assert html_response(conn, 404) =~ "Not Found"
  end
end

defmodule HiveWeb.PageControllerTest do
  use HiveWeb.ConnCase, async: true

  test "GET / redirects to forage", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/forage"
  end

  test "GET /ops redirects to Slack ops", %{conn: conn} do
    conn = get(conn, ~p"/ops")

    assert redirected_to(conn) == ~p"/ops/slack"
  end

  test "GET /ops/ redirects to Slack ops", %{conn: conn} do
    conn = get(conn, "/ops/")

    assert redirected_to(conn) == ~p"/ops/slack"
  end
end

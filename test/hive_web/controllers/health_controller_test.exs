defmodule HiveWeb.HealthControllerTest do
  use HiveWeb.ConnCase, async: true

  test "GET /live returns ok", %{conn: conn} do
    conn = get(conn, ~p"/live")

    assert response(conn, 200) == "ok"
  end

  test "GET /ready returns ok", %{conn: conn} do
    conn = get(conn, ~p"/ready")

    assert response(conn, 200) == "ok"
  end
end

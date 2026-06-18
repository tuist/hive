defmodule HiveWeb.PageControllerTest do
  use HiveWeb.ConnCase, async: true

  test "GET / redirects to forage", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/forage"
  end
end

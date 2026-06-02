defmodule HiveWeb.PageControllerTest do
  use HiveWeb.ConnCase, async: true

  test "GET / redirects to the feature requests forage source", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/forage/feature-requests"
  end
end

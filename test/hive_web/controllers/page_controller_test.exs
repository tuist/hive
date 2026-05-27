defmodule HiveWeb.PageControllerTest do
  use HiveWeb.ConnCase, async: true

  test "GET / renders the deployment placeholder", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "Hive"
  end
end

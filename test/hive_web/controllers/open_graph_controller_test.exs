defmodule HiveWeb.OpenGraphControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias HiveWeb.OpenGraph

  test "GET /open-graph/:page_id/:hash returns the image response", %{conn: conn} do
    data = %{
      description: "Description",
      eyebrow: "Forage",
      highlights: [],
      id: "login",
      path: "/login",
      title: "Log in"
    }

    stub(OpenGraph, :page, fn "login" -> {:ok, data} end)
    stub(OpenGraph, :valid_hash?, fn ^data, "valid" -> true end)

    stub(OpenGraph, :serve, fn conn, ^data ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> Plug.Conn.put_resp_header("content-type", "image/jpeg")
      |> Plug.Conn.send_resp(200, "jpeg")
    end)

    conn = get(conn, ~p"/open-graph/login/valid")

    assert response(conn, 200) == "jpeg"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
  end

  test "GET /open-graph/:page_id/:hash rejects stale hashes", %{conn: conn} do
    conn = get(conn, ~p"/open-graph/login/stale")

    assert response(conn, 404) == "Not found"
  end
end

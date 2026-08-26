defmodule HiveWeb.RobotsControllerTest do
  use HiveWeb.ConnCase, async: true

  use Mimic

  alias Hive.Auth

  test "advertises the sitemap for a public instance", %{conn: conn} do
    stub(Auth, :private?, fn -> false end)

    conn = get(conn, ~p"/robots.txt")

    assert response(conn, 200) ==
             "User-agent: *\nDisallow:\nSitemap: #{HiveWeb.Endpoint.url()}/sitemap.xml\n"

    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end

  test "blocks crawlers for a private instance", %{conn: conn} do
    stub(Auth, :private?, fn -> true end)

    conn = get(conn, ~p"/robots.txt")

    assert response(conn, 200) == "User-agent: *\nDisallow: /\n"
  end
end

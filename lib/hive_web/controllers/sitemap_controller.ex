defmodule HiveWeb.SitemapController do
  @moduledoc false

  use HiveWeb, :controller

  alias Hive.Auth
  alias HiveWeb.Sitemap

  def show(conn, _params) do
    if Auth.private?() do
      send_resp(conn, :not_found, "Not found")
    else
      conn
      |> put_resp_content_type("application/xml")
      |> put_resp_header("cache-control", "public, max-age=3600")
      |> send_resp(200, Sitemap.render())
    end
  end
end

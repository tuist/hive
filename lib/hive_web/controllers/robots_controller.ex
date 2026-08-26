defmodule HiveWeb.RobotsController do
  @moduledoc false

  use HiveWeb, :controller

  alias Hive.Auth
  alias HiveWeb.Endpoint

  def show(conn, _params) do
    body =
      if Auth.private?() do
        "User-agent: *\nDisallow: /\n"
      else
        "User-agent: *\nDisallow:\nSitemap: #{Endpoint.url()}/sitemap.xml\n"
      end

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, body)
  end
end

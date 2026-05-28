defmodule HiveWeb.PageController do
  use HiveWeb, :controller

  alias HiveWeb.PageHTML

  def home(conn, _params) do
    html(conn, Phoenix.HTML.Safe.to_iodata(PageHTML.app_page(conn)))
  end
end

defmodule HiveWeb.PageController do
  use HiveWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

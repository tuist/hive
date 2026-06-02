defmodule HiveWeb.PageController do
  use HiveWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/forage/feature-requests")
  end
end

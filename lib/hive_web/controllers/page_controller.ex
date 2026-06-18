defmodule HiveWeb.PageController do
  use HiveWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/forage")
  end

  def ops(conn, _params) do
    redirect(conn, to: ~p"/ops/slack")
  end
end

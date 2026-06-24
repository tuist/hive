defmodule HiveWeb.HealthController do
  use HiveWeb, :controller

  alias Hive.Repo

  def live(conn, _params) do
    send_resp(conn, 200, "ok")
  end

  def ready(conn, _params) do
    case Repo.query("SELECT 1", [], log: false) do
      {:ok, _result} -> send_resp(conn, 200, "ok")
      {:error, _reason} -> send_resp(conn, 503, "unavailable")
    end
  rescue
    DBConnection.ConnectionError -> send_resp(conn, 503, "unavailable")
    Postgrex.Error -> send_resp(conn, 503, "unavailable")
  end
end

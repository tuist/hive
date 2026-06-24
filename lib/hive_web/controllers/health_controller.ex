defmodule HiveWeb.HealthController do
  use HiveWeb, :controller

  alias Hive.Repo

  @ready_query "SELECT 1"
  @ready_timeout_ms 1_000

  def live(conn, _params) do
    send_resp(conn, 200, "ok")
  end

  def ready(conn, _params) do
    case Repo.query(@ready_query, [], log: false, timeout: @ready_timeout_ms) do
      {:ok, _result} -> send_resp(conn, 200, "ok")
      {:error, _reason} -> send_resp(conn, 503, "unavailable")
    end
  rescue
    _exception -> send_resp(conn, 503, "unavailable")
  end
end

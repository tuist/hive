defmodule HiveWeb.RequestOriginTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias HiveWeb.RequestOrigin

  test "uses the configured OAuth issuer" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:scheme, :http)
      |> Map.put(:host, "internal")
      |> Map.put(:port, 4000)
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-host", "mcp.hive.tuist.dev")
      |> put_req_header("x-forwarded-port", "8443")

    assert RequestOrigin.from_conn(conn) == "http://www.example.com"
  end
end

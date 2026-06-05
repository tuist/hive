defmodule HiveWeb.RequestOriginTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias HiveWeb.RequestOrigin

  test "uses the connection origin when forwarded headers are absent" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:scheme, :https)
      |> Map.put(:host, "hive.tuist.dev")
      |> Map.put(:port, 443)

    assert RequestOrigin.from_conn(conn) == "https://hive.tuist.dev"
  end

  test "uses forwarded origin headers" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:scheme, :http)
      |> Map.put(:host, "internal")
      |> Map.put(:port, 4000)
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-host", "mcp.hive.tuist.dev")
      |> put_req_header("x-forwarded-port", "8443")

    assert RequestOrigin.from_conn(conn) == "https://mcp.hive.tuist.dev:8443"
  end

  test "does not append the forwarded port when the host includes one" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:scheme, :http)
      |> Map.put(:host, "internal")
      |> Map.put(:port, 4000)
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-host", "mcp.hive.tuist.dev:9443")
      |> put_req_header("x-forwarded-port", "8443")

    assert RequestOrigin.from_conn(conn) == "https://mcp.hive.tuist.dev:9443"
  end

  test "uses the first value from comma-separated forwarded headers" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:scheme, :http)
      |> Map.put(:host, "internal")
      |> Map.put(:port, 4000)
      |> put_req_header("x-forwarded-proto", "https, http")
      |> put_req_header("x-forwarded-host", "hive.tuist.dev, internal")
      |> put_req_header("x-forwarded-port", "443, 4000")

    assert RequestOrigin.from_conn(conn) == "https://hive.tuist.dev"
  end
end

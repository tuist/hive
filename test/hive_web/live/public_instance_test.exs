defmodule HiveWeb.PublicInstanceTest do
  use HiveWeb.ConnCase, async: true

  describe "when instance is private (default)" do
    test "redirects unauthenticated users to login from /", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == "/login"
    end

    test "redirects unauthenticated users to login from /signals", %{conn: conn} do
      conn = get(conn, ~p"/signals")
      assert redirected_to(conn) == "/login"
    end

    test "redirects unauthenticated users to login from /settings", %{conn: conn} do
      conn = get(conn, ~p"/settings")
      assert redirected_to(conn) == "/login"
    end
  end

  describe "when instance is public" do
    setup do
      original = Application.get_env(:hive, :public)
      Application.put_env(:hive, :public, true)
      on_exit(fn -> Application.put_env(:hive, :public, original) end)
      :ok
    end

    test "allows unauthenticated users to view /signals", %{conn: conn} do
      conn = get(conn, ~p"/signals")
      assert html_response(conn, 200) =~ "Signals"
    end

    test "allows unauthenticated users to view /", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Signals"
    end

    test "allows unauthenticated users to view /swarms", %{conn: conn} do
      conn = get(conn, ~p"/swarms")
      assert html_response(conn, 200) =~ "Swarms"
    end

    test "redirects unauthenticated users from /settings to login", %{conn: conn} do
      conn = get(conn, ~p"/settings")
      assert redirected_to(conn) == "/login"
    end

    test "shows login button instead of account dropdown for guests", %{conn: conn} do
      conn = get(conn, ~p"/signals")
      assert html_response(conn, 200) =~ "Log in"
      refute html_response(conn, 200) =~ "account-dropdown"
    end

    test "hides settings sidebar item for guests", %{conn: conn} do
      conn = get(conn, ~p"/signals")
      refute html_response(conn, 200) =~ ~s(href="/settings")
    end
  end
end

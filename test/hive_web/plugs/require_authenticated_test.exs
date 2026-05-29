defmodule HiveWeb.Plugs.RequireAuthenticatedTest do
  use HiveWeb.ConnCase, async: false

  alias HiveWeb.Plugs.RequireAuthenticated

  setup do
    previous = Application.get_env(:hive, :auth)

    on_exit(fn ->
      Application.put_env(:hive, :auth, previous)
    end)
  end

  test "lets everyone through when the instance is public", %{conn: conn} do
    Application.put_env(:hive, :auth, visibility: "public")

    result = RequireAuthenticated.call(conn, [])

    refute result.halted
  end

  test "lets everyone through when no visibility is configured (defaults to public)", %{conn: conn} do
    Application.put_env(:hive, :auth, [])

    result = RequireAuthenticated.call(conn, [])

    refute result.halted
  end

  test "redirects unauthenticated users to /login when the instance is private", %{conn: conn} do
    Application.put_env(:hive, :auth, visibility: "private")

    result =
      conn
      |> Plug.Test.init_test_session(%{})
      |> RequireAuthenticated.call([])

    assert result.halted
    assert redirected_to(result) == ~p"/login"
  end

  test "lets authenticated users through when the instance is private", %{conn: conn} do
    Application.put_env(:hive, :auth, visibility: "private")

    result =
      conn
      |> Plug.Test.init_test_session(current_user: %{"email" => "alice@tuist.dev"})
      |> RequireAuthenticated.call([])

    refute result.halted
  end
end

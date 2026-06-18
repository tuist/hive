defmodule HiveWeb.Plugs.RequireAuthenticatedTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Auth
  alias HiveWeb.Plugs.RequireAuthenticated

  test "lets everyone through when the instance is public", %{conn: conn} do
    stub(Auth, :private?, fn -> false end)

    result = RequireAuthenticated.call(conn, [])

    refute result.halted
  end

  test "redirects unauthenticated requests to /login and stores the requested path", %{
    conn: conn
  } do
    stub(Auth, :private?, fn -> true end)
    stub(Auth, :current_user, fn _conn -> nil end)

    result =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Map.put(:request_path, "/ops/slack")
      |> Map.put(:query_string, "tab=workspaces")
      |> RequireAuthenticated.call([])

    assert result.halted
    assert redirected_to(result) == ~p"/login"
    assert get_session(result, :user_return_to) == "/ops/slack?tab=workspaces"
  end

  test "lets authenticated requests through when the instance is private", %{conn: conn} do
    stub(Auth, :private?, fn -> true end)
    stub(Auth, :current_user, fn _conn -> %{"email" => "alice@tuist.dev"} end)

    result = RequireAuthenticated.call(conn, [])

    refute result.halted
  end
end

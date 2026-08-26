defmodule HiveWeb.RouterTest do
  use HiveWeb.ConnCase, async: true

  use Mimic

  alias Hive.Auth

  test "private instances require sign in for every public dashboard collection" do
    stub(Auth, :private?, fn -> true end)
    stub(Auth, :current_user, fn _conn -> nil end)

    for path <- ~w(/ /forage /specs /postmortems /drops /domains /projects) do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> get(path)

      assert redirected_to(conn) == "/login"
    end
  end
end

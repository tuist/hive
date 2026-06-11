defmodule HiveWeb.ForageLive.PlaceholderTest do
  use HiveWeb.ConnCase, async: true

  test "feedback renders for anyone", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/forage/feedback")

    assert html =~ "Feedback"
  end
end

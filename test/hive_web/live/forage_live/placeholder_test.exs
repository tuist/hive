defmodule HiveWeb.ForageLive.PlaceholderTest do
  use HiveWeb.ConnCase, async: true

  test "feedback renders for anyone", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: target}}} = live(conn, ~p"/forage/feedback")

    assert target =~ "/forage?"
    assert target =~ "filter_type_val=feedback"
  end
end

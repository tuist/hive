defmodule HiveWeb.ForageLive.PlaceholderTest do
  use HiveWeb.ConnCase, async: true

  test "feedback renders for anyone", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/forage/feedback")

    assert html =~ "Feedback"
  end

  test "grafana alerts are hidden from guests", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/forage/feature-requests"}}} =
             live(conn, ~p"/forage/grafana-alerts")
  end

  test "grafana alerts render for members", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")

    {:ok, _view, html} = live(conn, ~p"/forage/grafana-alerts")

    assert html =~ "Grafana alerts"
  end
end

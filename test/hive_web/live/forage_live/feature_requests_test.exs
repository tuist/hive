defmodule HiveWeb.ForageLive.FeatureRequestsTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Forage

  test "renders the empty state when there are no requests", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/forage/feature-requests")

    assert html =~ "Feature requests"
    assert html =~ "No feature requests yet"
  end

  test "renders OpenGraph metadata in the root layout", %{conn: conn} do
    conn = get(conn, ~p"/forage/feature-requests")

    response = html_response(conn, 200)
    assert response =~ ~s|property="og:image"|
    assert response =~ ~s|name="twitter:card" content="summary_large_image"|
  end

  test "lists existing requests with requester and status, plus stats", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, _} =
      Forage.create_feature_request(
        %{"title" => "Dark mode", "description" => "Please add a dark theme to the dashboard."},
        user
      )

    {:ok, _view, html} = live(conn, ~p"/forage/feature-requests")

    assert html =~ "Dark mode"
    assert html =~ "Please add a dark theme to the dashboard."
    assert html =~ "Submitted by alice@example.com"
    assert html =~ "Open"
    assert html =~ "Total requests"
    assert html =~ "Contributors"
  end
end

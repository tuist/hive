defmodule HiveWeb.ForageLive.NewFeatureRequestTest do
  use HiveWeb.ConnCase, async: true

  test "redirects guests to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} =
             live(conn, ~p"/forage/feature-requests/new")
  end

  test "lets a signed-in user submit a request and shows it in the list", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, _html} = live(conn, ~p"/forage/feature-requests/new")

    result =
      view
      |> form("form[data-part='form']",
        feature_request: %{
          title: "GitHub sign-in",
          description: "Let requesters sign in with GitHub."
        }
      )
      |> render_submit()

    {:ok, _view, html} = follow_redirect(result, conn)

    assert html =~ "GitHub sign-in"
    assert html =~ "Submitted by alice@example.com"
  end

  test "surfaces validation errors with interpolated bindings", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, _html} = live(conn, ~p"/forage/feature-requests/new")

    html =
      view
      |> form("form[data-part='form']", feature_request: %{title: "", description: "short"})
      |> render_submit()

    assert html =~ "should be at least 10 character(s)"
    refute html =~ "%{count}"
  end
end

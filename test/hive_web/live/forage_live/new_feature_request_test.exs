defmodule HiveWeb.ForageLive.NewFeatureRequestTest do
  use HiveWeb.ConnCase, async: true

  test "redirects guests to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} =
             live(conn, ~p"/forage/new")
  end

  test "lets a signed-in user submit an item and shows it in the list", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, html} = live(conn, ~p"/forage/new")

    assert html =~ "New forage item"
    assert html =~ "Type"

    result =
      view
      |> form("form[data-part='form']",
        forage_item: %{
          type: "feedback",
          title: "GitHub sign-in",
          description: "Let requesters sign in with GitHub."
        }
      )
      |> render_submit()

    {:ok, _view, html} = follow_redirect(result, conn)

    assert html =~ "GitHub sign-in"
    assert html =~ "Feedback"
    assert html =~ "alice@example.com"
  end

  test "surfaces validation errors with interpolated bindings", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, _html} = live(conn, ~p"/forage/new")

    html =
      view
      |> form("form[data-part='form']",
        forage_item: %{type: "feature_request", title: "", description: "short"}
      )
      |> render_submit()

    assert html =~ "should be at least 10 character(s)"
    refute html =~ "%{count}"
  end
end

defmodule HiveWeb.HomeLiveTest do
  use HiveWeb.ConnCase, async: true

  test "introduces Hive and links every product area", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "From product signal to shipped work."
    assert html =~ "How work moves through Hive"
    assert html =~ "Choose where to start"

    for path <- ~w(/projects /domains /forage /specs /postmortems /drops) do
      assert html =~ ~s(href="#{path}")
    end
  end

  test "does not surface flights yet", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, ~s(#overview a[href="/flights"]))
  end

  test "marks Overview as the current dashboard section", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Overview"
    assert html =~ ~s(href="/")

    assert html =~
             ~r/<a href="\/" data-part="item">\s*<div class="noora-tab-menu-vertical" data-selected(?:>|="")/
  end

  test "includes page-specific OpenGraph metadata", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~s(property="og:title")
    assert html =~ "From product signal to shipped work"
    assert html =~ ~s(property="og:image")
  end
end

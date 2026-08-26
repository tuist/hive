defmodule HiveWeb.ForageLive.IndexTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Forage
  alias Hive.Forage.Comment
  alias Hive.Repo

  test "renders the empty state when there are no forage items", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/forage")

    assert html =~ "Forage"
    assert html =~ "No forage items found"
    assert html =~ "Items"
  end

  test "renders OpenGraph metadata in the root layout", %{conn: conn} do
    conn = get(conn, ~p"/forage")

    response = html_response(conn, 200)
    assert response =~ ~s|property="og:image"|
    assert response =~ ~s|name="twitter:card" content="summary_large_image"|
  end

  test "lists existing manual forage items with type, requester, and status", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, item} =
      Forage.create_forage_item(
        %{
          "type" => "bug_report",
          "title" => "Dark mode crash",
          "description" => "Opening the dashboard with dark mode enabled crashes."
        },
        user
      )

    {:ok, view, html} = live(conn, ~p"/forage")

    assert html =~ "Dark mode crash"
    assert html =~ "Opening the dashboard with dark mode enabled crashes."
    assert html =~ "Bug report"
    assert html =~ "alice@example.com"
    assert html =~ "Open"
    assert html =~ "Open signals"

    item_path = "/forage/items/manual/#{item.id}"

    assert {:error, {:live_redirect, %{to: ^item_path}}} =
             view
             |> element("a[data-part='item-title-link']", "Dark mode crash")
             |> render_click()

    {:ok, _view, html} = live(conn, ~p"/forage/items/manual/#{item.id}")

    assert html =~ "Details"
    assert html =~ "Create spec"
  end

  test "allows item authors to edit their manual forage items", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, item} =
      Forage.create_forage_item(
        %{
          "type" => "bug_report",
          "title" => "Dark mode crash",
          "description" => "Opening the dashboard with dark mode enabled crashes."
        },
        user
      )

    {:ok, view, html} = live(conn, ~p"/forage/items/manual/#{item.id}")

    assert html =~ ~s|phx-click="edit_item"|

    html = render_click(view, "edit_item")
    assert html =~ "Save item"

    html =
      view
      |> form("form[data-part='item-edit-form']",
        forage_item_edit: %{
          type: "feedback",
          title: "Dark mode feedback",
          description: "The dashboard should explain what happened instead of crashing."
        }
      )
      |> render_submit()

    assert Repo.reload!(item).title == "Dark mode feedback"
    assert html =~ "Dark mode feedback"
    refute html =~ "Dark mode crash"
  end

  test "hides manual item edit controls from other users", %{conn: conn} do
    {_author_conn, author} = sign_in(conn, "alice@example.com")
    {conn, _other_user} = sign_in(conn, "bob@example.com")

    {:ok, item} =
      Forage.create_forage_item(
        %{
          "type" => "bug_report",
          "title" => "Dark mode crash",
          "description" => "Opening the dashboard with dark mode enabled crashes."
        },
        author
      )

    {:ok, view, html} = live(conn, ~p"/forage/items/manual/#{item.id}")

    refute html =~ ~s|phx-click="edit_item"|

    html = render_click(view, "edit_item")
    refute html =~ "Save item"
  end

  test "allows signed-in users to comment on manual forage items and edit their own comments", %{
    conn: conn
  } do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, item} =
      Forage.create_forage_item(
        %{
          "type" => "feature_request",
          "title" => "Import discussions",
          "description" => "Import public GitHub discussions into forage."
        },
        user
      )

    {:ok, view, html} = live(conn, ~p"/forage/items/manual/#{item.id}")
    assert html =~ "No comments yet"

    html =
      view
      |> form("form[data-part='comment-form']", comment: %{body: "This would help triage."})
      |> render_submit()

    assert html =~ "This would help triage."

    comment = Repo.one!(Comment)
    html = render_click(view, "edit_comment", %{"id" => comment.id})

    assert html =~ "Save comment"

    html =
      view
      |> form("form[data-part='comment-edit-form']",
        comment_edit: %{body: "This would help triage quickly."}
      )
      |> render_submit()

    assert html =~ "This would help triage quickly."
    refute html =~ "This would help triage.</p>"
  end

  test "renders feature requests at their stable public URL", %{conn: conn} do
    conn = get(conn, ~p"/forage/feature-requests")

    response = html_response(conn, 200)
    assert response =~ "Feature requests · Hive"
    assert response =~ ~s|name="description" content="Public feature requests|

    assert response =~
             ~s|rel="canonical" href="#{HiveWeb.Endpoint.url()}/forage/feature-requests"|
  end
end

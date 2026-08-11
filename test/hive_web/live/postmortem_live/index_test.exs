defmodule HiveWeb.PostmortemLive.IndexTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Postmortems

  test "lists published postmortems and exposes feed discovery", %{conn: conn} do
    {conn, user} = sign_in(conn, "postmortem-viewer@example.com")

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Queue delay\n\nA delayed worker backlog affected notifications."},
        user
      )

    {:ok, view, html} = live(conn, ~p"/postmortems")

    assert html =~ "Queue delay"
    assert html =~ ~s(href="/postmortems/atom.xml")
    assert html =~ ~s(href="/postmortems/rss.xml")
    assert html =~ ~s(property="og:image")
    assert has_element?(view, "#postmortems-feeds-dropdown")
    assert has_element?(view, "#postmortems-search")
    assert has_element?(view, "#postmortems-filter")
    assert html =~ "Published"
    assert html =~ "postmortem-viewer@example.com"
    assert {:ok, _show_view, show_html} = live(conn, ~p"/postmortems/#{postmortem.number}")
    assert show_html =~ "A delayed worker backlog affected notifications."
    assert show_html =~ ~s(property="og:image")
  end

  test "paginates postmortems", %{conn: conn} do
    {conn, user} = sign_in(conn, "postmortem-pagination@example.com")

    Enum.each(1..21, fn number ->
      {:ok, _postmortem} =
        Postmortems.publish_postmortem(
          %{"body" => "# Incident #{number}\n\nA documented incident with enough detail."},
          user
        )
    end)

    {:ok, view, _html} = live(conn, ~p"/postmortems")

    assert has_element?(view, "[data-part=pagination]")
  end

  test "keeps Markdown edits in the textarea", %{conn: conn} do
    {conn, user} = sign_in(conn, "postmortem-editor@example.com")

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Original incident\n\nThe original account has enough detail."},
        user
      )

    {:ok, view, _html} = live(conn, ~p"/postmortems/#{postmortem.number}/edit")

    assert has_element?(view, "#postmortem-domains")

    html =
      render_change(view, "validate", %{
        "postmortem" => %{
          "body" => "# Updated incident\n\nThe revised account has enough detail."
        }
      })

    assert html =~ "Updated incident"
    assert html =~ "/100000"
  end

  test "manages postmortem action items", %{conn: conn} do
    {conn, user} = sign_in(conn, "postmortem-action-items@example.com")

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry delay\n\nPackage resolution was delayed."},
        user
      )

    {:ok, view, _html} = live(conn, ~p"/postmortems/#{postmortem.number}")

    assert has_element?(view, "#new-action-item-modal")
    assert has_element?(view, "#new-action-item-modal [data-part=trigger]")

    assert {:ok, action_item} =
             Postmortems.create_action_item(
               postmortem,
               %{
                 "title" => "Add registry monitoring",
                 "description" => "Alert when package resolution latency rises."
               },
               user
             )

    {:ok, view, _html} = live(conn, ~p"/postmortems/#{postmortem.number}")

    html =
      render_submit(view, "update_action_item", %{
        "id" => action_item.id,
        "action_item" => %{
          "title" => "x",
          "description" => "Keep the description visible."
        }
      })

    assert html =~ ~s(value="x")
    assert html =~ "Keep the description visible."

    assert Postmortems.get_postmortem_by_number!(postmortem.number).action_items
           |> hd()
           |> Map.get(:title) ==
             "Add registry monitoring"
  end

  test "shows public postmortems to anonymous visitors and hides private ones", %{conn: conn} do
    {_member_conn, user} = sign_in(conn, "postmortem-visibility@example.com")

    {:ok, public_postmortem} =
      Postmortems.publish_postmortem(
        %{
          "body" => "# Public registry incident\n\nThis account is safe to share.",
          "visibility" => "public"
        },
        user
      )

    {:ok, private_postmortem} =
      Postmortems.publish_postmortem(
        %{
          "body" => "# Private registry incident\n\nThis account is for members only.",
          "visibility" => "private"
        },
        user
      )

    {:ok, _view, html} = live(Phoenix.ConnTest.build_conn(), ~p"/postmortems")
    assert html =~ "Public registry incident"
    refute html =~ "Private registry incident"

    assert {:ok, _view, html} =
             live(Phoenix.ConnTest.build_conn(), ~p"/postmortems/#{public_postmortem.number}")

    assert html =~ "This account is safe to share."

    assert {:error, {:live_redirect, %{to: "/postmortems"}}} =
             live(Phoenix.ConnTest.build_conn(), ~p"/postmortems/#{private_postmortem.number}")
  end
end

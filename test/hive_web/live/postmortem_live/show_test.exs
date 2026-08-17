defmodule HiveWeb.PostmortemLive.ShowTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Postmortems

  @description """
  Validated against `main`. Still open.

  - `server/lib/tuist/registry.ex:62` defaults the sync limit to 1,000.
  - The production overlay sets no override.
  """

  defp postmortem_with_action_item(conn, email, attrs) do
    {conn, user} = sign_in(conn, email)

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry outage\n\nThe registry served stale catalog entries."},
        user
      )

    {:ok, action_item} = Postmortems.create_action_item(postmortem, attrs, user)

    {conn, postmortem, action_item}
  end

  test "renders the description preview as plain text and the expansion as Markdown", %{
    conn: conn
  } do
    {conn, postmortem, action_item} =
      postmortem_with_action_item(conn, "postmortem-expand@example.com", %{
        "title" => "Cap the catalog pass",
        "description" => @description
      })

    {:ok, view, _html} = live(conn, ~p"/postmortems/#{postmortem.number}")

    row = "#action-item-#{action_item.id}"
    expanded = "#action-item-#{action_item.id}-expanded"

    # The collapsed preview is flattened, so Markdown syntax does not leak into
    # the table cell. (The raw body still appears elsewhere on the page, in the
    # edit modal's textarea, so this has to assert on the cell itself.)
    preview =
      view
      |> element("#{row} [data-type=text_and_description] [data-part=description]")
      |> render()

    assert preview =~ "server/lib/tuist/registry.ex:62 defaults the sync limit to 1,000."
    refute preview =~ "`"
    refute preview =~ "<code>"

    assert has_element?(view, "#{row}[data-expandable]")
    refute has_element?(view, expanded)

    view |> element(row) |> render_click()

    assert has_element?(view, expanded)

    expanded_html = view |> element(expanded) |> render()

    assert expanded_html =~ "<code>server/lib/tuist/registry.ex:62</code>"
    assert expanded_html =~ "<li>"

    view |> element(row) |> render_click()

    refute has_element?(view, expanded)
  end

  test "leaves an action item without a description unexpandable", %{conn: conn} do
    {conn, postmortem, action_item} =
      postmortem_with_action_item(conn, "postmortem-no-description@example.com", %{
        "title" => "Confirm the owners"
      })

    {:ok, view, _html} = live(conn, ~p"/postmortems/#{postmortem.number}")

    assert has_element?(view, "#action-item-#{action_item.id}")
    refute has_element?(view, "#action-item-#{action_item.id}[data-expandable]")
  end

  test "toggling an action item does not expand its row", %{conn: conn} do
    {conn, postmortem, action_item} =
      postmortem_with_action_item(conn, "postmortem-toggle@example.com", %{
        "title" => "Cap the catalog pass",
        "description" => @description
      })

    {:ok, view, _html} = live(conn, ~p"/postmortems/#{postmortem.number}")

    view
    |> element(~s([phx-click=toggle_action_item][phx-value-id="#{action_item.id}"]))
    |> render_click()

    assert has_element?(view, "#action-item-#{action_item.id}")
    refute has_element?(view, "#action-item-#{action_item.id}-expanded")
  end
end

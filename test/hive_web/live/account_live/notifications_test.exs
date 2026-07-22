defmodule HiveWeb.AccountLive.NotificationsTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Forage
  alias Hive.Notifications
  alias Hive.Specs

  test "lets a signed-in user manage global notification timing", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, view, html} = live(conn, ~p"/account/notifications")

    assert html =~ "Choose the updates Hive sends"
    assert html =~ "New Forage items"
    assert html =~ "Domain drops"
    assert has_element?(view, "#notification-following-table .noora-table-empty-state")

    assert has_element?(
             view,
             ~s(.noora-button-group [phx-value-topic="forage_new_items"][phx-value-cadence="off"][data-selected])
           )

    render_click(view, "set_global", %{
      "topic" => "forage_new_items",
      "cadence" => "daily"
    })

    assert Notifications.get_subscription(user, :forage_new_items).cadence == :daily

    assert has_element?(
             view,
             ~s(.noora-button-group [phx-value-topic="forage_new_items"][phx-value-cadence="daily"][data-selected])
           )

    render_click(view, "set_global", %{
      "topic" => "forage_new_items",
      "cadence" => "off"
    })

    refute Notifications.subscribed?(user, :forage_new_items)
  end

  test "redirects anonymous visitors to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/account/notifications")
  end

  test "filters, searches, and paginates followed items", %{conn: conn} do
    {conn, user} = sign_in(conn, "follower@example.com")

    for index <- 1..11 do
      title = if index == 11, do: "Needle proposal", else: "Followed spec #{index}"
      {:ok, _spec} = Specs.create_spec(%{"title" => title, "body" => "Proposal body."}, user)
    end

    {:ok, forage_item} =
      Forage.create_feature_request(
        %{"title" => "Followed feature request", "description" => "Feature details."},
        user
      )

    {:ok, view, html} = live(conn, ~p"/account/notifications")

    assert has_element?(view, "#notification-following-filter")
    assert has_element?(view, "#notification-following-search")
    assert has_element?(view, ~s([data-part="pagination"]))
    assert length(Regex.scan(~r/id="following-/, html)) == 10

    html = render_patch(view, ~p"/account/notifications?page=2")
    assert length(Regex.scan(~r/id="following-/, html)) == 2

    html = render_patch(view, ~p"/account/notifications?q=Needle%20proposal")
    assert html =~ "Needle proposal"
    refute html =~ "Followed spec 1"
    refute html =~ "Followed feature request"

    html =
      render_patch(
        view,
        ~p"/account/notifications?filter_kind_op===&filter_kind_val=forage_item_updates"
      )

    assert html =~ forage_item.title
    refute html =~ "Needle proposal"
  end
end

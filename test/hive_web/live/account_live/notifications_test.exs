defmodule HiveWeb.AccountLive.NotificationsTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Notifications

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
end

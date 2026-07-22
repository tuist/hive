defmodule HiveWeb.NotificationUnsubscribeControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts
  alias Hive.Notifications
  alias Hive.Notifications.Email

  test "one-click unsubscribe disables every subscription in the email category", %{conn: conn} do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "alice@example.com",
        provider: "test",
        provider_uid: "alice@example.com"
      })

    Notifications.follow_spec(user, Ecto.UUID.generate())
    Notifications.follow_spec(user, Ecto.UUID.generate())
    token = Email.unsubscribe_token(user, :spec_updates)

    conn = get(conn, ~p"/notifications/unsubscribe?token=#{token}")
    assert html_response(conn, 200) =~ "Stop Followed spec updates?"

    conn = post(build_conn(), ~p"/notifications/unsubscribe?token=#{token}")
    assert html_response(conn, 200) =~ "You are unsubscribed"
    assert Notifications.list_subscriptions(user, :spec_updates) == []
  end

  test "a link about a single spec only stops updates for that spec", %{conn: conn} do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "bob@example.com",
        provider: "test",
        provider_uid: "bob@example.com"
      })

    {:ok, kept} = Notifications.follow_spec(user, Ecto.UUID.generate())
    {:ok, dropped} = Notifications.follow_spec(user, Ecto.UUID.generate())
    token = Email.unsubscribe_token(user, :spec_updates, dropped.scope_id)

    conn = get(conn, ~p"/notifications/unsubscribe?token=#{token}")
    html = html_response(conn, 200)
    assert html =~ "Stop updates about this one?"
    assert html =~ "Stop Followed spec updates"

    conn = post(build_conn(), ~p"/notifications/unsubscribe?token=#{token}")
    assert html_response(conn, 200) =~ "no longer email you about that item"

    assert [remaining] = Notifications.list_subscriptions(user, :spec_updates)
    assert remaining.scope_id == kept.scope_id
  end

  test "rejects an invalid token", %{conn: conn} do
    conn = get(conn, ~p"/notifications/unsubscribe?token=invalid")
    assert html_response(conn, 404) =~ "This link is no longer valid"
  end
end

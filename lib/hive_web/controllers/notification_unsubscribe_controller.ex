defmodule HiveWeb.NotificationUnsubscribeController do
  use HiveWeb, :controller

  alias Hive.Accounts
  alias Hive.Notifications
  alias Hive.Notifications.Email

  def show(conn, %{"token" => token}) do
    conn = put_layout(conn, false)

    case Email.verify_unsubscribe_token(token) do
      {:ok, _user_id, topic} ->
        render(conn, :show,
          page_title: "Unsubscribe · Hive",
          token: token,
          topic_label: Notifications.topic_label(topic),
          open_graph: open_graph("Unsubscribe from email updates")
        )

      {:error, :invalid_token} ->
        conn
        |> put_status(:not_found)
        |> render(:invalid,
          page_title: "Invalid unsubscribe link · Hive",
          open_graph: open_graph("Invalid unsubscribe link")
        )
    end
  end

  def show(conn, _params) do
    conn
    |> put_layout(false)
    |> put_status(:not_found)
    |> render(:invalid,
      page_title: "Invalid unsubscribe link · Hive",
      open_graph: open_graph("Invalid unsubscribe link")
    )
  end

  def create(conn, %{"token" => token}) do
    conn = put_layout(conn, false)

    case Email.verify_unsubscribe_token(token) do
      {:ok, user_id, topic} ->
        if user = Accounts.get_user(user_id), do: Notifications.unsubscribe_topic(user, topic)

        render(conn, :success,
          page_title: "Email updates disabled · Hive",
          topic_label: Notifications.topic_label(topic),
          open_graph: open_graph("Email updates disabled")
        )

      {:error, :invalid_token} ->
        conn
        |> put_status(:not_found)
        |> render(:invalid,
          page_title: "Invalid unsubscribe link · Hive",
          open_graph: open_graph("Invalid unsubscribe link")
        )
    end
  end

  def create(conn, _params), do: show(conn, %{})

  defp open_graph(title) do
    [open_graph: open_graph] =
      HiveWeb.OpenGraph.assigns(%{
        description: "Manage the email updates sent by this Hive instance.",
        highlights: ["Email preferences", "One-click unsubscribe", "Hive account"],
        id: "notification-unsubscribe",
        path: "/notifications/unsubscribe",
        section_label: "Notifications",
        title: title
      })

    open_graph
  end
end

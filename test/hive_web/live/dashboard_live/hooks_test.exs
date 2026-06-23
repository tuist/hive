defmodule HiveWeb.DashboardLive.HooksTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias HiveWeb.DashboardLive.Hooks

  defp socket, do: %Phoenix.LiveView.Socket{}

  describe "assign_chrome/2" do
    test "assigns guest chrome when the session has no user" do
      socket = Hooks.assign_chrome(socket(), %{})

      assert socket.assigns.current_user == nil
      assert socket.assigns.signed_in? == false
      assert socket.assigns.user_name == "Guest"
      assert socket.assigns.user_email == nil
      assert socket.assigns.avatar_color == "gray"
      assert socket.assigns.product_name == "Hive"
      assert socket.assigns.current_path == "/"
      assert is_binary(socket.assigns.csrf_token)
      refute Enum.any?(socket.assigns.forage_sources, &(&1.id == :grafana_alerts))
    end

    test "loads the user and member chrome from the session user id" do
      {:ok, user} =
        Accounts.upsert_from_auth(%{
          email: "alice@example.com",
          provider: "test",
          provider_uid: "alice"
        })

      socket = Hooks.assign_chrome(socket(), %{"user_id" => user.id})

      assert socket.assigns.current_user.id == user.id
      assert socket.assigns.signed_in? == true
      assert socket.assigns.user_name == "alice@example.com"
      assert socket.assigns.user_email == "alice@example.com"
      assert socket.assigns.avatar_color == "purple"
      assert Enum.any?(socket.assigns.forage_sources, &(&1.id == :grafana_alerts))
    end
  end

  describe "put_current_path/3" do
    test "tracks the path from the uri" do
      {:cont, socket} =
        Hooks.put_current_path(%{}, "https://hive.test/forage/bug-reports", socket())

      assert socket.assigns.current_path == "/forage/bug-reports"
    end

    test "tracks the path and query string from the uri" do
      {:cont, socket} =
        Hooks.put_current_path(%{}, "https://hive.test/drops?domain=tuist&page=2", socket())

      assert socket.assigns.current_path == "/drops?domain=tuist&page=2"
    end
  end
end

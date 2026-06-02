defmodule HiveWeb.ForageLiveTest do
  use HiveWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Hive.Accounts
  alias Hive.Forage

  defp sign_in(conn, email) do
    {:ok, user} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    {Plug.Test.init_test_session(conn, %{user_id: user.id}), user}
  end

  describe "feature requests list" do
    test "renders the empty state when there are no requests", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/forage/feature-requests")

      assert html =~ "Feature requests"
      assert html =~ "No feature requests yet"
    end

    test "lists existing requests with requester and status, plus stats", %{conn: conn} do
      {conn, user} = sign_in(conn, "alice@example.com")

      {:ok, _} =
        Forage.create_feature_request(
          %{"title" => "Dark mode", "description" => "Please add a dark theme to the dashboard."},
          user
        )

      {:ok, _view, html} = live(conn, ~p"/forage/feature-requests")

      assert html =~ "Dark mode"
      assert html =~ "Please add a dark theme to the dashboard."
      assert html =~ "Submitted by alice@example.com"
      assert html =~ "Open"
      assert html =~ "Total requests"
      assert html =~ "Contributors"
    end

    test "redirects guests away from the new-request page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} =
               live(conn, ~p"/forage/feature-requests/new")
    end

    test "lets a signed-in user submit a request and shows it in the list", %{conn: conn} do
      {conn, _user} = sign_in(conn, "alice@example.com")

      {:ok, view, _html} = live(conn, ~p"/forage/feature-requests/new")

      result =
        view
        |> form("form[data-part='form']",
          feature_request: %{
            title: "GitHub sign-in",
            description: "Let requesters sign in with GitHub."
          }
        )
        |> render_submit()

      {:ok, _view, html} = follow_redirect(result, conn)

      assert html =~ "GitHub sign-in"
      assert html =~ "Submitted by alice@example.com"
    end

    test "surfaces validation errors with interpolated bindings", %{conn: conn} do
      {conn, _user} = sign_in(conn, "alice@example.com")

      {:ok, view, _html} = live(conn, ~p"/forage/feature-requests/new")

      html =
        view
        |> form("form[data-part='form']",
          feature_request: %{title: "", description: "short"}
        )
        |> render_submit()

      assert html =~ "should be at least 10 character(s)"
      refute html =~ "%{count}"
    end
  end

  describe "placeholder sources" do
    test "feedback renders for anyone", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/forage/feedback")

      assert html =~ "Feedback"
    end

    test "grafana alerts are hidden from guests", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/forage/feature-requests"}}} =
               live(conn, ~p"/forage/grafana-alerts")
    end

    test "grafana alerts render for members", %{conn: conn} do
      {conn, _user} = sign_in(conn, "pedro@tuist.dev")

      {:ok, _view, html} = live(conn, ~p"/forage/grafana-alerts")

      assert html =~ "Grafana alerts"
    end
  end
end

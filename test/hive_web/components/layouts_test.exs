defmodule HiveWeb.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias HiveWeb.Layouts

  describe "app/1" do
    test "renders the document shell with title, favicon, stylesheet, and body" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Layouts.app title="Sign in · Hive">Body content here</Layouts.app>
        """)

      assert html =~ "<!doctype html>"
      assert html =~ "Sign in · Hive"
      assert html =~ ~s(rel="icon")
      assert html =~ ~s(href="/assets/js/app.css")
      assert html =~ "Body content here"
    end
  end

  describe "dashboard/1" do
    defp render_dashboard(assigns) do
      rendered_to_string(~H"""
      <Layouts.dashboard
        product_name={@product_name}
        user_name={@user_name}
        user_email={@user_email}
        avatar_color={@avatar_color}
        auth_enabled?={@auth_enabled?}
        signed_in?={@signed_in?}
        csrf_token={@csrf_token}
        current_path={@current_path}
        forage_sources={@forage_sources}
      >
        <p>Main content</p>
      </Layouts.dashboard>
      """)
    end

    defp assigns(overrides \\ %{}) do
      Map.merge(
        %{
          product_name: "Hive",
          user_name: "alice@example.com",
          user_email: "alice@example.com",
          avatar_color: "purple",
          auth_enabled?: false,
          signed_in?: true,
          csrf_token: "csrf-token-123",
          current_path: "/forage/feature-requests",
          forage_sources: [
            %{
              id: :feature_requests,
              label: "Feature requests",
              icon: "bulb",
              path: "/forage/feature-requests"
            },
            %{
              id: :bug_reports,
              label: "Bug reports",
              icon: "file_alert",
              path: "/forage/bug-reports"
            }
          ]
        },
        overrides
      )
    end

    test "renders the product name and the slotted content" do
      html = render_dashboard(assigns())

      assert html =~ "Hive"
      assert html =~ "Main content"
    end

    test "shows the account menu and a logout form when signed in" do
      html = render_dashboard(assigns(%{signed_in?: true}))

      assert html =~ "account-dropdown"
      assert html =~ "alice@example.com"
      assert html =~ ~s(action="/logout")
      assert html =~ "csrf-token-123"
      assert html =~ "Log out"
      refute html =~ ">Sign in<"
    end

    test "shows a sign-in button and no account menu for guests" do
      html = render_dashboard(assigns(%{signed_in?: false}))

      assert html =~ ~s(href="/login")
      assert html =~ "Sign in"
      refute html =~ "account-dropdown"
      refute html =~ "Log out"
    end

    test "lists the visible forage sources" do
      html = render_dashboard(assigns())

      assert html =~ "Feature requests"
      assert html =~ "Bug reports"
      assert html =~ "/forage/feature-requests"
      assert html =~ "/forage/bug-reports"
    end

    test "shows product settings to signed-in users" do
      html = render_dashboard(assigns(%{signed_in?: true, current_path: "/settings/products"}))

      assert html =~ "Settings"
      assert html =~ "Products"
      assert html =~ "/settings/products"
    end

    test "hides settings from guests" do
      html = render_dashboard(assigns(%{signed_in?: false}))

      refute html =~ "/settings/products"
    end
  end
end

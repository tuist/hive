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
        settings_enabled?={@settings_enabled?}
        csrf_token={@csrf_token}
        current_path={@current_path}
        forage_sources={@forage_sources}
      >
        <p>Main content</p>
      </Layouts.dashboard>
      """)
    end

    defp render_account(assigns) do
      rendered_to_string(~H"""
      <Layouts.account
        product_name={@product_name}
        user_name={@user_name}
        user_email={@user_email}
        avatar_color={@avatar_color}
        signed_in?={@signed_in?}
        csrf_token={@csrf_token}
        current_path={@current_path}
      >
        <p>Account content</p>
      </Layouts.account>
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
          settings_enabled?: true,
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

    test "renders the meadow name and the slotted content" do
      html = render_dashboard(assigns())

      assert html =~ "Hive"
      assert html =~ "Main content"
    end

    test "shows the account menu and a logout form when signed in" do
      html = render_dashboard(assigns(%{signed_in?: true}))

      assert html =~ "account-dropdown"
      assert html =~ "alice@example.com"
      assert html =~ ~s(href="/account/identities")
      assert html =~ "Account"
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
      refute html =~ ~s(href="/account/identities")
    end

    test "lists the visible forage sources" do
      html = render_dashboard(assigns())

      assert html =~ "Feature requests"
      assert html =~ "Bug reports"
      assert html =~ "/forage/feature-requests"
      assert html =~ "/forage/bug-reports"
    end

    test "shows meadow settings when settings are enabled" do
      html =
        render_dashboard(
          assigns(%{
            signed_in?: true,
            settings_enabled?: true,
            current_path: "/settings/meadows"
          })
        )

      assert html =~ "Settings"
      assert html =~ "Meadows"
      assert html =~ "/settings/meadows"
    end

    test "hides settings when settings are disabled" do
      html = render_dashboard(assigns(%{signed_in?: true, settings_enabled?: false}))

      refute html =~ "/settings/meadows"
    end

    test "does not show account navigation in the dashboard sidebar" do
      html = render_dashboard(assigns(%{signed_in?: true, current_path: "/account/identities"}))

      assert html =~ ~s(href="/account/identities")
      refute html =~ ~s(<span data-part="label">Identities</span>)
    end
  end

  describe "account/1" do
    test "renders account content with account sidebar navigation" do
      html = render_account(assigns(%{current_path: "/account/identities"}))

      assert html =~ "Account content"
      assert html =~ "Identities"
      assert html =~ "/account/identities"
      refute html =~ "Feature requests"
      refute html =~ "/settings/meadows"
    end
  end
end

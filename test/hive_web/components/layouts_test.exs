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

  describe "flash_group/1" do
    test "renders info and error flash messages as alerts" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Layouts.flash_group flash={%{"info" => "Connected Slack.", "error" => "Slack rejected the install."}} />
        """)

      assert html =~ "Connected Slack."
      assert html =~ "Slack rejected the install."
      assert html =~ ~s(data-status="success")
      assert html =~ ~s(data-status="error")
    end

    test "stays empty when there are no flash messages" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Layouts.flash_group flash={%{}} />
        """)

      refute html =~ "flash-stack"
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
        admin?={@admin?}
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

    defp render_ops(assigns) do
      rendered_to_string(~H"""
      <Layouts.ops
        product_name={@product_name}
        user_name={@user_name}
        user_email={@user_email}
        avatar_color={@avatar_color}
        signed_in?={@signed_in?}
        csrf_token={@csrf_token}
        current_path={@current_path}
      >
        <p>Ops content</p>
      </Layouts.ops>
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
          admin?: false,
          csrf_token: "csrf-token-123",
          current_path: "/forage",
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

    test "renders the domain name and the slotted content" do
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

    test "links to the unified forage page" do
      html = render_dashboard(assigns())

      assert html =~ "Forage"
      assert html =~ ~s(href="/forage")
      refute html =~ "Feature requests"
      refute html =~ "/forage/feature-requests"
    end

    test "shows Domains at the top of the sidebar for any visitor" do
      html =
        render_dashboard(
          assigns(%{
            signed_in?: false,
            current_path: "/domains"
          })
        )

      assert html =~ "Domains"
      assert html =~ ~s(href="/domains")
    end

    test "does not show account navigation in the dashboard sidebar" do
      html = render_dashboard(assigns(%{signed_in?: true, current_path: "/account/identities"}))

      assert html =~ ~s(href="/account/identities")
      refute html =~ ~s(<span data-part="label">Identities</span>)
    end

    test "does not show ops navigation in the dashboard sidebar" do
      member_html = render_dashboard(assigns(%{admin?: false}))
      admin_html = render_dashboard(assigns(%{admin?: true, current_path: "/ops/slack"}))

      refute member_html =~ ~s(href="/ops/slack")
      refute admin_html =~ "Ops"
      refute admin_html =~ ~s(href="/ops/slack")
    end
  end

  describe "account/1" do
    test "renders account content with account sidebar navigation" do
      html = render_account(assigns(%{current_path: "/account/identities"}))

      assert html =~ "Account content"
      assert html =~ "Identities"
      assert html =~ "/account/identities"
      refute html =~ "Slack"
      refute html =~ "/ops/slack"
      refute html =~ "Feature requests"
      refute html =~ "/domains"
    end
  end

  describe "ops/1" do
    test "renders ops content with ops sidebar navigation" do
      html = render_ops(assigns(%{current_path: "/ops/slack"}))

      assert html =~ "Ops content"
      assert html =~ "Slack"
      assert html =~ "/ops/slack"
      refute html =~ ~s(<span data-part="label">Identities</span>)
    end
  end
end

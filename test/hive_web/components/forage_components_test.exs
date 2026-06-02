defmodule HiveWeb.ForageComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Hive.Accounts.User
  alias Hive.Forage
  alias Hive.Forage.FeatureRequest
  alias HiveWeb.ForageComponents

  describe "feature_requests/1" do
    test "renders the empty state when there are no requests" do
      assigns = %{source: Forage.get_source!(:feature_requests)}

      html =
        rendered_to_string(~H"""
        <ForageComponents.feature_requests
          source={@source}
          feature_requests={[]}
          signed_in?={false}
        />
        """)

      assert html =~ "No feature requests yet"
      assert html =~ "Total requests"
    end

    test "renders a request with its requester and status" do
      request = %FeatureRequest{
        title: "Dark mode",
        description: "Please add a dark theme.",
        status: :open,
        user: %User{email: "alice@example.com"}
      }

      assigns = %{source: Forage.get_source!(:feature_requests), requests: [request]}

      html =
        rendered_to_string(~H"""
        <ForageComponents.feature_requests
          source={@source}
          feature_requests={@requests}
          signed_in?={true}
        />
        """)

      assert html =~ "Dark mode"
      assert html =~ "Please add a dark theme."
      assert html =~ "Submitted by alice@example.com"
      assert html =~ "Open"
    end
  end

  describe "new_feature_request/1" do
    test "renders the request form" do
      form = to_form(Forage.change_feature_request(), as: :feature_request)
      assigns = %{form: form}

      html =
        rendered_to_string(~H"""
        <ForageComponents.new_feature_request form={@form} user_name="alice@example.com" />
        """)

      assert html =~ "Requesting as"
      assert html =~ "alice@example.com"
      assert html =~ "Title"
      assert html =~ "Description"
      assert html =~ ~s(phx-submit="save")
    end
  end

  describe "placeholder/1" do
    test "renders the not-connected-yet copy for a source" do
      assigns = %{source: Forage.get_source!(:bug_reports)}

      html =
        rendered_to_string(~H"""
        <ForageComponents.placeholder source={@source} signed_in?={false} />
        """)

      assert html =~ "Bug reports"
      assert html =~ "not connected yet"
    end
  end
end

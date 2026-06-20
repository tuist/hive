defmodule HiveWeb.ForageComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Hive.Accounts.User
  alias Hive.Forage
  alias Hive.Forage.FeatureRequest
  alias Hive.Forage.GitHubIssue
  alias Hive.Domains.GitHubRepository
  alias Hive.Domains.Domain
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

  describe "new_item/1" do
    test "renders the item form" do
      form = to_form(Forage.change_forage_item(), as: :forage_item)
      assigns = %{form: form}

      html =
        rendered_to_string(~H"""
        <ForageComponents.new_item form={@form} user_name="alice@example.com" />
        """)

      assert html =~ "Requesting as"
      assert html =~ "alice@example.com"
      assert html =~ "Type"
      assert html =~ "Title"
      assert html =~ "Description"
      assert html =~ ~s(phx-submit="save")
    end
  end

  describe "github_issues/1" do
    test "renders inline code spans in titles and skips heading-only excerpts" do
      domain = %Domain{name: "hive"}
      repository = %GitHubRepository{owner: "tuist", name: "tuist"}

      issue = %GitHubIssue{
        number: 42,
        title: "Static framework with `.metal` produces `default.metallib`",
        body: "### What happened?\n\nThe `tuist generate` command misbehaves."
      }

      assigns = %{
        source: Forage.get_source!(:github_issues),
        entries: [{repository, issue, [domain]}],
        stats: %{state_label: "open", total: 1, repositories: 1, domains: 1},
        available_filters: [],
        active_filters: []
      }

      html =
        rendered_to_string(~H"""
        <ForageComponents.github_issues
          source={@source}
          signed_in?={false}
          entries={@entries}
          stats={@stats}
          available_filters={@available_filters}
          active_filters={@active_filters}
        />
        """)

      assert html =~
               ~s(Static framework with <code>.metal</code> produces <code>default.metallib</code>)

      refute html =~ "### What happened?"
      assert html =~ "The <code>tuist generate</code> command misbehaves."
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

defmodule HiveWeb.ForageComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Hive.Accounts.User
  alias Hive.Domains.Domain
  alias Hive.Domains.GitHubRepository
  alias Hive.Forage
  alias Hive.Forage.FeatureRequest
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.Item
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

  describe "item_detail/1" do
    test "renders metadata and body in separate cards" do
      item = %Item{
        id: "manual:feature-request-1",
        type: :feature_request,
        origin: :manual,
        source_record_id: "feature-request-1",
        title: "Import GitHub discussions",
        body: "Use Markdown for longer context.",
        status: :open,
        source_label: "Hive",
        external_label: "Submitted by alice@example.com",
        requester_label: "alice@example.com",
        updated_at: ~U[2026-06-24 10:00:00Z],
        comments: [],
        comments_status: :loaded,
        domains: []
      }

      assigns = %{
        item: item,
        can_edit_item?: false,
        can_create_spec?: false,
        can_comment_item?: false,
        editing_item?: false,
        item_edit_form: to_form(Forage.change_forage_item(), as: :forage_item_edit),
        comment_form: to_form(Forage.change_comment(), as: :comment),
        edit_comment_form: to_form(Forage.change_comment(), as: :comment_edit),
        editing_comment_id: nil,
        signed_in?: false,
        current_path: "/forage/items/manual/feature-request-1",
        current_user: nil
      }

      html =
        rendered_to_string(~H"""
        <ForageComponents.item_detail
          item={@item}
          can_edit_item?={@can_edit_item?}
          can_create_spec?={@can_create_spec?}
          can_comment_item?={@can_comment_item?}
          editing_item?={@editing_item?}
          item_edit_form={@item_edit_form}
          comment_form={@comment_form}
          edit_comment_form={@edit_comment_form}
          editing_comment_id={@editing_comment_id}
          signed_in?={@signed_in?}
          current_path={@current_path}
          current_user={@current_user}
        />
        """)

      assert html =~ ~s(data-part="metadata-card")
      assert html =~ ~s(data-part="body-card")
      assert html =~ "Metadata"
      assert html =~ "Details"
      assert html =~ "Use Markdown for longer context."
      assert html =~ ~r/data-part="metadata-card".*data-part="body-card"/s
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

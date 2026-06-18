defmodule Hive.ForageTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Forage
  alias Hive.Forage.GitHubIssue
  alias Hive.GitHub.Issues
  alias Hive.Meadows

  defp user(attrs \\ %{}) do
    {:ok, user} =
      Accounts.upsert_from_auth(
        Map.merge(
          %{email: "alice@example.com", provider: "test", provider_uid: "alice"},
          attrs
        )
      )

    user
  end

  defp user_with_email(prefix) do
    suffix = unique()
    user(%{email: "#{prefix}-#{suffix}@example.com", provider_uid: "#{prefix}-#{suffix}"})
  end

  defp meadow_with_repo!(opts) do
    suffix = unique()
    visibility = Keyword.get(opts, :visibility, "public")
    repo_visibility = Keyword.get(opts, :repo_visibility, "public")

    {:ok, meadow} =
      Meadows.create_meadow(%{
        name: "forage-#{suffix}",
        visibility: visibility,
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo#{suffix}",
        github_repository_visibility: repo_visibility
      })

    meadow
  end

  defp unique, do: System.unique_integer([:positive])

  describe "get_source!/1" do
    test "returns the source with the given id" do
      assert Forage.get_source!(:feature_requests).id == :feature_requests
    end

    test "raises for an unknown source" do
      assert_raise ArgumentError, ~r/unknown forage source/, fn ->
        Forage.get_source!(:nope)
      end
    end
  end

  describe "visible_sources/1" do
    test "hides organization-only forage sources from guests" do
      assert Forage.visible_sources(nil) |> Enum.map(& &1.id) == [
               :feature_requests,
               :bug_reports,
               :feedback
             ]
    end

    test "includes organization-only forage sources for members" do
      assert Forage.visible_sources(user()) |> Enum.map(& &1.id) == [
               :feature_requests,
               :bug_reports,
               :feedback,
               :github_issues,
               :grafana_alerts
             ]
    end
  end

  describe "can_access?/2" do
    test "public sources are readable by guests" do
      assert Forage.can_access?(Forage.get_source!(:feature_requests), nil)
    end

    test "organization sources are hidden from guests" do
      refute Forage.can_access?(Forage.get_source!(:grafana_alerts), nil)
    end

    test "organization sources are readable by members" do
      assert Forage.can_access?(Forage.get_source!(:grafana_alerts), user())
    end

    test "github_issues is hidden from guests when no public/public pair exists" do
      meadow_with_repo!(visibility: "private", repo_visibility: "public")

      refute Forage.can_access?(Forage.get_source!(:github_issues), nil)
    end

    test "github_issues is visible to guests when at least one public/public pair exists" do
      meadow_with_repo!(visibility: "public", repo_visibility: "public")

      assert Forage.can_access?(Forage.get_source!(:github_issues), nil)
    end

    test "github_issues is hidden from guests when the repo is private even if the meadow is public" do
      meadow_with_repo!(visibility: "public", repo_visibility: "private")

      refute Forage.can_access?(Forage.get_source!(:github_issues), nil)
    end

    test "github_issues is visible to members even when no meadows are connected" do
      stub(Auth, :member?, fn _user -> true end)

      assert Forage.can_access?(
               Forage.get_source!(:github_issues),
               user_with_email("forage-member")
             )
    end
  end

  describe "accessible_meadows_with_repositories/1" do
    test "returns no pairs for a guest when every pair is gated by a private side" do
      meadow_with_repo!(visibility: "public", repo_visibility: "private")

      assert Forage.accessible_meadows_with_repositories(nil) == []
    end

    test "returns every pair to a member regardless of visibility" do
      stub(Auth, :member?, fn _user -> true end)

      meadow = meadow_with_repo!(visibility: "private", repo_visibility: "private")

      assert [{%{name: name}, %{owner: owner, name: repo_name}}] =
               Forage.accessible_meadows_with_repositories(user_with_email("forage-pairs"))

      assert name == meadow.name
      assert owner == hd(meadow.github_repositories).owner
      assert repo_name == hd(meadow.github_repositories).name
    end

    test "skips meadows without a connected repository" do
      {:ok, _} = Meadows.create_meadow(%{name: "forage-no-repo-#{unique()}"})

      assert Forage.accessible_meadows_with_repositories(nil) == []
    end
  end

  describe "can_create?/2" do
    test "guests cannot create on a public creatable source" do
      refute Forage.can_create?(Forage.get_source!(:feature_requests), nil)
    end

    test "members can create on a public creatable source" do
      assert Forage.can_create?(Forage.get_source!(:feature_requests), user())
    end

    test "nobody can create on a non-creatable source" do
      refute Forage.can_create?(Forage.get_source!(:grafana_alerts), user())
    end
  end

  describe "change_feature_request/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = Forage.change_feature_request()
    end

    test "is valid for sound attributes" do
      changeset =
        Forage.change_feature_request(%Hive.Forage.FeatureRequest{}, %{
          "title" => "A title",
          "description" => "A description that is long enough."
        })

      assert changeset.valid?
    end
  end

  describe "create_feature_request/2" do
    test "associates the request with the signed-in user" do
      user = user()

      {:ok, feature_request} =
        Forage.create_feature_request(
          %{"title" => "GitHub sign-in", "description" => "Let requesters sign in with GitHub."},
          user
        )

      assert feature_request.user_id == user.id
      assert feature_request.type == :feature_request
      assert feature_request.visibility == :public
      assert feature_request.status == :open
    end

    test "returns an error changeset for invalid attributes" do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Forage.create_feature_request(%{"title" => "", "description" => "short"}, user())
    end
  end

  describe "create_forage_item/2" do
    test "stores the selected manual forage item type" do
      user = user()

      {:ok, item} =
        Forage.create_forage_item(
          %{
            "type" => "bug_report",
            "title" => "Crash on launch",
            "description" => "The dashboard crashes during launch."
          },
          user
        )

      assert item.type == :bug_report
      assert item.user_id == user.id
      assert item.status == :open
    end
  end

  describe "update_forage_item/3" do
    test "allows the submitting user to update their manual item" do
      user = user()

      {:ok, item} =
        Forage.create_forage_item(
          %{
            "type" => "bug_report",
            "title" => "Crash on launch",
            "description" => "The dashboard crashes during launch."
          },
          user
        )

      assert {:ok, item} =
               Forage.update_forage_item(
                 item,
                 %{
                   "type" => "feedback",
                   "title" => "Launch flow is confusing",
                   "description" => "The dashboard launch flow needs clearer feedback."
                 },
                 user
               )

      assert item.type == :feedback
      assert item.title == "Launch flow is confusing"
    end

    test "rejects updates from other users" do
      author = user_with_email("forage-author")
      other_user = user_with_email("forage-other")

      {:ok, item} =
        Forage.create_forage_item(
          %{
            "type" => "bug_report",
            "title" => "Crash on launch",
            "description" => "The dashboard crashes during launch."
          },
          author
        )

      assert Forage.update_forage_item(
               item,
               %{"title" => "Hijacked", "description" => "This should not land."},
               other_user
             ) == {:error, :unauthorized}
    end
  end

  describe "forage item comments" do
    test "fetches GitHub issue comments on demand without syncing them" do
      meadow = meadow_with_repo!([])
      repository = hd(meadow.github_repositories)

      Forage.reconcile_repository_github_issues(repository, [
        %{number: 42, title: "Crash on launch", body: "Detail"}
      ])

      issue = Repo.get_by!(GitHubIssue, github_repository_id: repository.id, number: 42)

      expect(Issues, :list_comments, fn fetched_repository, 42, [] ->
        assert fetched_repository.id == repository.id

        {:ok,
         [
           %Issues.Comment{
             id: 1,
             body: "I can reproduce this from GitHub.",
             html_url: "https://github.com/owner/repo/issues/42#issuecomment-1",
             user_login: "octo",
             user_avatar_url: "https://avatar/octo",
             created_at: "2026-06-01T00:00:00Z"
           }
         ]}
      end)

      assert {:ok, selected} =
               Forage.get_item_for_user("github_issue:#{issue.id}", nil,
                 fetch_github_comments?: true
               )

      assert [
               %Issues.Comment{
                 body: "I can reproduce this from GitHub.",
                 user_login: "octo"
               }
             ] = selected.comments

      assert Repo.aggregate(Forage.Comment, :count) == 0
    end

    test "adds and returns comments for manual forage items" do
      user = user()

      {:ok, item} =
        Forage.create_forage_item(
          %{
            "type" => "feature_request",
            "title" => "GitHub discussions import",
            "description" => "Import public GitHub discussions into forage."
          },
          user
        )

      assert {:ok, comment} = Forage.add_comment(item, %{"body" => "Worth doing."}, user)
      assert comment.user_id == user.id

      assert {:ok, selected} = Forage.get_item_for_user("manual:#{item.id}", nil)
      assert [%{body: "Worth doing.", user: %{email: "alice@example.com"}}] = selected.comments
    end

    test "lets comment authors update their comments" do
      user = user()

      {:ok, item} =
        Forage.create_forage_item(
          %{
            "type" => "feedback",
            "title" => "Helpful dashboard",
            "description" => "The dashboard makes prioritization much clearer."
          },
          user
        )

      {:ok, comment} = Forage.add_comment(item, %{"body" => "Initial note."}, user)

      assert {:ok, comment} =
               Forage.update_comment(comment, %{"body" => "Updated note."}, user)

      assert comment.body == "Updated note."
    end

    test "rejects comment updates from other users" do
      author = user_with_email("forage-comment-author")
      other_user = user_with_email("forage-comment-other")

      {:ok, item} =
        Forage.create_forage_item(
          %{
            "type" => "feedback",
            "title" => "Helpful dashboard",
            "description" => "The dashboard makes prioritization much clearer."
          },
          author
        )

      {:ok, comment} = Forage.add_comment(item, %{"body" => "Initial note."}, author)

      assert Forage.update_comment(comment, %{"body" => "Hijacked."}, other_user) ==
               {:error, :unauthorized}
    end
  end

  describe "list_feature_requests/0" do
    test "preloads the requesting user" do
      user = user()

      {:ok, _} =
        Forage.create_feature_request(
          %{"title" => "GitHub sign-in", "description" => "Let requesters sign in with GitHub."},
          user
        )

      assert [feature_request] = Forage.list_feature_requests()
      assert feature_request.user.id == user.id
      assert feature_request.user.email == "alice@example.com"
    end

    test "only returns feature request typed manual items" do
      user = user()

      {:ok, _feedback} =
        Forage.create_forage_item(
          %{
            "type" => "feedback",
            "title" => "Great dashboard",
            "description" => "The dashboard makes planning easier."
          },
          user
        )

      assert Forage.list_feature_requests() == []
    end
  end

  describe "list_forage_items_for_user/2" do
    test "returns manual items in the unified read model" do
      user = user()

      {:ok, _feedback} =
        Forage.create_forage_item(
          %{
            "type" => "feedback",
            "title" => "Great dashboard",
            "description" => "The dashboard makes planning easier."
          },
          user
        )

      assert {[item], %{total_count: 1}} =
               Forage.list_forage_items_for_user(nil, type: :feedback)

      assert item.type == :feedback
      assert item.title == "Great dashboard"
      assert item.source_label == "Hive"
      assert item.external_label == user.email
    end
  end
end
